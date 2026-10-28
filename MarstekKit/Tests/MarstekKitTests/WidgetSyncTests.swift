import Foundation
import Testing
@testable import MarstekKit

@Suite struct WidgetSyncTests {
    let t0 = kyivDate(12, 0)

    func payload(soc: Double = 64, at date: Date) -> WidgetPayload {
        var snapshot = BatterySnapshot.normalize(es: ESStatus(batSoc: soc, batCap: 5120), bat: nil, mode: "Manual",
                                                 invertSign: false, at: date)
        snapshot.tempC = 25
        return WidgetPayload(snapshot: snapshot, smoothedNetPowerW: 0, today: DailyCounters(),
                             history: HistoryStore(), dodPercent: 88, deviceName: "VenusE 3.0")
    }

    @Test func signatureIgnoresUpdateTime() {
        let a = DashboardModel(payload: payload(at: t0), now: t0, calendar: kyiv)
        let b = DashboardModel(payload: payload(at: t0 + 15), now: t0 + 15, calendar: kyiv)
        let c = DashboardModel(payload: payload(soc: 63, at: t0 + 15), now: t0 + 15, calendar: kyiv)
        #expect(a.signature == b.signature)
        #expect(a.signature != c.signature)
    }

    @Test func firstPayloadWritesAndReloads() {
        var sync = WidgetSync()
        #expect(sync.decide(payload(at: t0), now: t0, calendar: kyiv) == .init(write: true, reload: true))
    }

    @Test func unchangedContentDoesNotReload() {
        var sync = WidgetSync()
        _ = sync.decide(payload(at: t0), now: t0, calendar: kyiv)
        #expect(sync.decide(payload(at: t0 + 15), now: t0 + 15, calendar: kyiv) == .init(write: false, reload: false))
        // History still has to reach disk about once a minute.
        #expect(sync.decide(payload(at: t0 + 60), now: t0 + 60, calendar: kyiv).write)
        #expect(!sync.decide(payload(at: t0 + 3600), now: t0 + 3600, calendar: kyiv).reload)
    }

    @Test func changeWithinFloorIsDeferredNotLost() {
        var sync = WidgetSync()
        _ = sync.decide(payload(at: t0), now: t0, calendar: kyiv)
        let early = sync.decide(payload(soc: 63, at: t0 + 30), now: t0 + 30, calendar: kyiv)
        #expect(early == .init(write: true, reload: false))
        let later = sync.decide(payload(soc: 63, at: t0 + WidgetSync.minReloadInterval), now: t0 + WidgetSync.minReloadInterval, calendar: kyiv)
        #expect(later == .init(write: true, reload: true))
    }

    @Test func payloadHistoryIsTrimmedTo24h() {
        var history = HistoryStore()
        history.append(HistorySample(t: t0 - 3 * 86400, soc: 10))
        history.append(HistorySample(t: t0 - 3600, soc: 20))
        #expect(history.trimmed(endingAt: t0).samples.map(\.soc) == [20])
    }

    @Test func historyFileRoundTrip() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        var history = HistoryStore()
        history.append(HistorySample(t: t0, soc: 64))
        let store = PayloadStore(directory: dir)
        #expect(store.loadHistory() == nil)
        try store.saveHistory(history)
        #expect(store.loadHistory() == history)
    }
}
