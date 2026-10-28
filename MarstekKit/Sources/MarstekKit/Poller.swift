import Foundation

public struct PollerSettings: Sendable, Equatable {
    public var host: String
    public var port: UInt16 = 30000
    public var dodPercent: Double = 88
    public var invertSign = false
    public var interval: Duration = .seconds(15)
    public var deviceName: String?

    public init(host: String, port: UInt16 = 30000, dodPercent: Double = 88, invertSign: Bool = false,
                interval: Duration = .seconds(15), deviceName: String? = nil) {
        self.host = host
        self.port = port
        self.dodPercent = dodPercent
        self.invertSign = invertSign
        self.interval = interval
        self.deviceName = deviceName
    }
}

/// Polls the battery on a fixed cadence and turns replies into `WidgetPayload`s.
/// Fields that didn't arrive keep their last known value instead of becoming zero.
public actor Poller {
    static let modeRefresh: TimeInterval = 300
    static let failuresBeforeRediscovery = 3

    private var settings: PollerSettings
    private let transport: DatagramTransport
    private var client: MarstekClient
    private let onUpdate: @Sendable (WidgetPayload) -> Void
    private let onDeviceChange: @Sendable (DeviceInfo) -> Void
    private let calendar: Calendar
    private let minSpacing: Duration
    private let timeout: Duration
    private let discoveryTimeout: Duration

    private var lastES: ESStatus?
    private var lastESAt: Date?
    private var lastBat: BatStatus?
    private var lastMode: String?
    private var lastModeAt: Date?
    private var smoother = PowerSmoother()
    private var today: DailyCounters
    private var history: HistoryStore
    private var consecutiveFailures = 0
    private var loop: Task<Void, Never>?
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init(settings: PollerSettings, transport: DatagramTransport, initial: WidgetPayload?,
                onUpdate: @escaping @Sendable (WidgetPayload) -> Void,
                onDeviceChange: @escaping @Sendable (DeviceInfo) -> Void,
                calendar: Calendar = .current, minSpacing: Duration = .seconds(1.5),
                timeout: Duration = .seconds(3), discoveryTimeout: Duration = .seconds(3)) {
        self.settings = settings
        self.transport = transport
        self.onUpdate = onUpdate
        self.onDeviceChange = onDeviceChange
        self.calendar = calendar
        self.minSpacing = minSpacing
        self.timeout = timeout
        self.discoveryTimeout = discoveryTimeout
        client = MarstekClient(host: settings.host, port: settings.port, transport: transport,
                               minSpacing: minSpacing, timeout: timeout)
        today = initial?.today ?? DailyCounters()
        history = initial?.history ?? HistoryStore()
        lastMode = initial?.snapshot.mode
    }

    public func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                await runCycle(now: Date())
                try? await Task.sleep(for: settings.interval)
            }
        }
    }

    public func stop() {
        loop?.cancel()
        loop = nil
    }

    public func updateSettings(_ new: PollerSettings) async {
        if new.port != settings.port {
            client = MarstekClient(host: new.host, port: new.port, transport: transport,
                                   minSpacing: minSpacing, timeout: timeout)
        } else {
            await client.setHost(new.host)
        }
        settings = new
    }

    public func runCycle(now: Date) async {
        await exclusive { await cycle(now: now) }
    }

    /// Discovery for the Settings button, on the poller's socket and never in the
    /// middle of a cycle, so its broadcast can't swallow or be swallowed by poll replies.
    public func discoverDevices() async -> [DeviceInfo] {
        await exclusive {
            await MarstekClient.discover(transport: transport, port: settings.port, timeout: discoveryTimeout)
        }
    }

    private func exclusive<T: Sendable>(_ body: () async -> T) async -> T {
        while busy { await withCheckedContinuation { waiters.append($0) } }
        busy = true
        defer {
            busy = false
            if !waiters.isEmpty { waiters.removeFirst().resume() }
        }
        return await body()
    }

    private func cycle(now: Date) async {
        let es = try? await client.call("ES.GetStatus", as: ESStatus.self)
        let bat = try? await client.call("Bat.GetStatus", as: BatStatus.self)
        guard es != nil || bat != nil else {
            consecutiveFailures += 1
            if consecutiveFailures >= Self.failuresBeforeRediscovery { await rediscover() }
            return
        }
        consecutiveFailures = 0
        if let es {
            lastES = Self.merge(es, over: lastES)
            lastESAt = now
        }
        if let bat { lastBat = Self.merge(bat, over: lastBat) }

        if lastModeAt.map({ now.timeIntervalSince($0) > Self.modeRefresh }) ?? true,
           let mode = try? await client.call("ES.GetMode", as: ESMode.self) {
            lastMode = mode.mode ?? lastMode
            lastModeAt = now
        }

        let snapshot = BatterySnapshot.normalize(es: esView(answered: es != nil, now: now), bat: lastBat, mode: lastMode,
                                                 invertSign: settings.invertSign, at: now)
        var smoothed: Double?
        if let grid = snapshot.gridPowerW {
            let net = netBatteryPowerW(gridPowerW: grid, socketPowerW: snapshot.socketPowerW ?? 0)
            smoothed = es != nil ? smoother.add(net, at: now) : smoother.value
        }
        today.update(chargeWh: snapshot.chargeCounterWh, dischargeWh: snapshot.dischargeCounterWh, at: now, calendar: calendar)
        if (es?.batSoc ?? bat?.soc) != nil, let soc = snapshot.soc { history.append(HistorySample(t: now, soc: soc)) }

        onUpdate(WidgetPayload(snapshot: snapshot, smoothedNetPowerW: smoothed, today: today,
                               history: history, dodPercent: settings.dodPercent, deviceName: settings.deviceName))
    }

    /// The ES values to show this cycle. When ES.GetStatus stayed silent, its last
    /// reply must not pass for current data: SOC comes from Bat.GetStatus instead,
    /// lifetime counters wait for a fresh reply (or "today" would count overnight),
    /// and power is kept only briefly so a single dropped reply doesn't blank the arrows.
    private func esView(answered: Bool, now: Date) -> ESStatus? {
        guard !answered, var old = lastES else { return lastES }
        old.batSoc = nil
        old.totalGridInputEnergy = nil
        old.totalGridOutputEnergy = nil
        let maxAge = 2 * Double(settings.interval.components.seconds)
        if lastESAt.map({ now.timeIntervalSince($0) > maxAge }) ?? true {
            old.ongridPower = nil
            old.offgridPower = nil
            old.batPower = nil
        }
        return old
    }

    /// The router may have handed the battery a new address.
    private func rediscover() async {
        consecutiveFailures = 0
        let devices = await MarstekClient.discover(transport: transport, port: settings.port, timeout: discoveryTimeout)
        guard let device = devices.first, let ip = device.ip, ip != settings.host else { return }
        settings.host = ip
        settings.deviceName = device.device ?? settings.deviceName
        await client.setHost(ip)
        onDeviceChange(device)
    }

    private static func merge(_ new: ESStatus, over old: ESStatus?) -> ESStatus {
        ESStatus(batSoc: new.batSoc ?? old?.batSoc, batCap: new.batCap ?? old?.batCap,
                 pvPower: new.pvPower ?? old?.pvPower, ongridPower: new.ongridPower ?? old?.ongridPower,
                 offgridPower: new.offgridPower ?? old?.offgridPower, batPower: new.batPower ?? old?.batPower,
                 totalGridOutputEnergy: new.totalGridOutputEnergy ?? old?.totalGridOutputEnergy,
                 totalGridInputEnergy: new.totalGridInputEnergy ?? old?.totalGridInputEnergy)
    }

    private static func merge(_ new: BatStatus, over old: BatStatus?) -> BatStatus {
        BatStatus(soc: new.soc ?? old?.soc, batTemp: new.batTemp ?? old?.batTemp,
                  batCapacity: new.batCapacity ?? old?.batCapacity,
                  ratedCapacity: new.ratedCapacity ?? old?.ratedCapacity,
                  chargFlag: new.chargFlag ?? old?.chargFlag, dischrgFlag: new.dischrgFlag ?? old?.dischrgFlag)
    }
}
