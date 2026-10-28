import Foundation
import Testing
@testable import MarstekKit

/// Collects callback values from the poller.
final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [T] = []
    func add(_ item: T) { lock.lock(); items.append(item); lock.unlock() }
    var all: [T] { lock.lock(); defer { lock.unlock() }; return items }
}

@Suite struct PollerTests {
    let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func poller(_ transport: FakeTransport, updates: Box<WidgetPayload>, hosts: Box<DeviceInfo> = Box(),
                spacing: Duration = .zero) -> Poller {
        Poller(settings: PollerSettings(host: "192.168.1.50", deviceName: "VenusE 3.0"), transport: transport, initial: nil,
               onUpdate: { updates.add($0) }, onDeviceChange: { hosts.add($0) },
               calendar: kyiv, minSpacing: spacing, timeout: .milliseconds(20), discoveryTimeout: .milliseconds(20))
    }

    @Test func keepsLastKnownOnPartialFailure() async throws {
        // First cycle: everything answers.
        let transport = FakeTransport { id, method, _ in
            switch method {
            case "ES.GetStatus": return [reply(id: id, #"{"bat_soc":64,"bat_cap":5120,"ongrid_power":0}"#)]
            case "Bat.GetStatus": return [reply(id: id, batResult)]
            case "ES.GetMode": return [reply(id: id, #"{"mode":"Manual"}"#)]
            default: return []
            }
        }
        let updates = Box<WidgetPayload>()
        let p = poller(transport, updates: updates)
        await p.runCycle(now: t0)
        // Second cycle: Bat.GetStatus never answers.
        await transport.setResponder { id, method, _ in
            method == "ES.GetStatus" ? [reply(id: id, #"{"bat_soc":63,"bat_cap":5120,"ongrid_power":0}"#)] : []
        }
        await p.runCycle(now: t0 + 15)
        let last = try #require(updates.all.last)
        #expect(updates.all.count == 2)
        #expect(last.snapshot.tempC == 25.0)
        #expect(last.snapshot.soc == 63)
        #expect(last.snapshot.mode == "Manual")
    }

    @Test func staleESAfterWakeIsNotTreatedAsFresh() async throws {
        // Evening, day 1: everything answers; charge counter 9000, SOC 90, charging 500 W.
        let evening = #"{"bat_soc":90,"bat_cap":5120,"ongrid_power":\#(DeviceConventions.gridChargingIsPositive ? 500 : -500),"offgrid_power":0,"total_grid_input_energy":9000,"total_grid_output_energy":3000}"#
        let transport = FakeTransport { id, method, _ in
            switch method {
            case "ES.GetStatus": [reply(id: id, evening)]
            case "Bat.GetStatus": [reply(id: id, #"{"soc":90,"bat_temp":24}"#)]
            default: [reply(id: id, #"{"mode":"Manual"}"#)]
            }
        }
        let updates = Box<WidgetPayload>()
        let p = poller(transport, updates: updates)
        await p.runCycle(now: kyivDate(22, 0, dayOffset: -1))

        // Next morning after sleep: ES is silent, Bat answers with the real SOC.
        await transport.setResponder { id, method, _ in
            method == "Bat.GetStatus" ? [reply(id: id, #"{"soc":64,"bat_temp":21}"#)] : []
        }
        await p.runCycle(now: kyivDate(8, 0))
        let morning = try #require(updates.all.last)
        #expect(morning.snapshot.soc == 64)
        #expect(morning.snapshot.gridPowerW == nil)
        #expect(morning.history.samples.last?.soc == 64)

        // ES returns later with the overnight counter: today must start from here.
        await transport.setResponder { id, method, _ in
            switch method {
            case "ES.GetStatus": [reply(id: id, #"{"bat_soc":64,"bat_cap":5120,"ongrid_power":0,"total_grid_input_energy":9900,"total_grid_output_energy":3000}"#)]
            default: [reply(id: id, #"{"soc":64}"#)]
            }
        }
        await p.runCycle(now: kyivDate(8, 1))
        #expect(updates.all.last?.today.todayChargedWh == 0)
    }

    @Test func noEmitWhenAllFail() async {
        let updates = Box<WidgetPayload>()
        await poller(FakeTransport { _, _, _ in [] }, updates: updates).runCycle(now: t0)
        #expect(updates.all.isEmpty)
    }

    @Test func rediscoversAfterThreeFailures() async throws {
        let device = Data(#"{"id":0,"src":"VenusE 3.1-a1b2c3d4e5f6","result":{"device":"VenusE 3.1","ip":"192.168.1.51"}}"#.utf8)
        let transport = FakeTransport { id, method, host in
            if method == "Marstek.GetDevice" { return [device] }
            guard host == "192.168.1.51" else { return [] }
            return method == "ES.GetStatus" ? [reply(id: id, esResult)] : [reply(id: id, batResult)]
        }
        let updates = Box<WidgetPayload>(), hosts = Box<DeviceInfo>()
        let p = poller(transport, updates: updates, hosts: hosts)
        for i in 0..<3 { await p.runCycle(now: t0 + Double(i) * 15) }
        #expect(hosts.all.map(\.ip) == ["192.168.1.51"])
        #expect(hosts.all.first?.device == "VenusE 3.1")
        await p.runCycle(now: t0 + 45)
        #expect(await transport.sent.last?.host == "192.168.1.51")
        #expect(updates.all.count == 1)
        #expect(updates.all.first?.deviceName == "VenusE 3.1")
    }

    @Test func manualDiscoveryWaitsForTheCycle() async {
        let device = Data(#"{"id":0,"result":{"device":"VenusE 3.0","ip":"192.168.1.50"}}"#.utf8)
        let transport = FakeTransport { id, method, _ in
            method == "Marstek.GetDevice" ? [device] : [reply(id: id, esResult)]
        }
        let p = poller(transport, updates: Box(), spacing: .milliseconds(30))
        async let cycle: Void = p.runCycle(now: t0)
        async let found = p.discoverDevices()
        _ = await (cycle, found)
        let methods = await transport.sent.map(\.method)
        // Discovery runs before or after the cycle, never between its requests.
        #expect(methods.first == "Marstek.GetDevice" || methods.last == "Marstek.GetDevice")
    }

    @Test func modePolledEvery5Min() async {
        let transport = FakeTransport { id, method, _ in
            method == "ES.GetMode" ? [reply(id: id, #"{"mode":"Manual"}"#)] : [reply(id: id, esResult)]
        }
        let p = poller(transport, updates: Box())
        await p.runCycle(now: t0)
        await p.runCycle(now: t0 + 15)
        #expect(await transport.sent.filter { $0.method == "ES.GetMode" }.count == 1)
        await p.runCycle(now: t0 + 301)
        #expect(await transport.sent.filter { $0.method == "ES.GetMode" }.count == 2)
    }

    @Test func payloadCarriesForecastInputs() async throws {
        let transport = FakeTransport { id, method, _ in
            method == "Bat.GetStatus" ? [reply(id: id, batResult)] : [reply(id: id, esResult)]
        }
        let updates = Box<WidgetPayload>()
        await poller(transport, updates: updates).runCycle(now: t0)
        let payload = try #require(updates.all.first)
        // esResult has raw ongrid_power -420.
        let expected: Double = DeviceConventions.gridChargingIsPositive ? -420 : 420
        #expect(payload.smoothedNetPowerW == expected)
        #expect(payload.dodPercent == 88)
        #expect(payload.history.samples.count == 1)
    }

    @Test func payloadRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var history = HistoryStore()
        history.append(HistorySample(t: t0, soc: 64))
        let payload = WidgetPayload(
            snapshot: BatterySnapshot.normalize(es: ESStatus(batSoc: 64, batCap: 5120), bat: nil, mode: "Manual", invertSign: false, at: t0),
            smoothedNetPowerW: -420, today: DailyCounters(), history: history, dodPercent: 88, deviceName: "VenusE 3.0")
        let store = PayloadStore(directory: dir)
        #expect(store.load() == nil)
        try store.save(payload)
        #expect(store.load() == payload)
    }
}
