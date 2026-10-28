import Foundation
import MarstekKit
import Observation
import OSLog
import ServiceManagement
import WidgetKit

/// Owns the poller, persists settings in the App Group, and feeds the widget.
@MainActor @Observable
final class AppState {
    private(set) var payload: WidgetPayload?
    private(set) var status = ""
    /// Ticks every 30 s so time-dependent labels (stale brackets) refresh without new data.
    private(set) var clock = Date()

    var host: String { didSet { save(); pushSettings() } }
    var port: Int { didSet { save(); pushSettings() } }
    var dodPercent: Double { didSet { save(); pushSettings() } }
    var invertSign: Bool { didSet { save(); pushSettings() } }
    var showMenuBarIcon: Bool { didSet { save() } }
    var language: AppLanguage {
        didSet {
            save()
            WidgetCenter.shared.reloadTimelines(ofKind: "MarstekWidget")
        }
    }
    var text: L10n { L10n(language.resolved()) }
    private var deviceName: String? { didSet { save() } }

    private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    private let defaults = AppGroup.defaults
    private let store = AppGroup.store
    private var poller: Poller?
    /// `start()` suspends during discovery; this keeps settings changes made
    /// meanwhile from launching a second poller.
    private var isStarting = false
    private var sync = WidgetSync()
    private var lastHistorySave: Date?
    static let historySaveInterval: TimeInterval = 600
    private let log = Logger(subsystem: "com.nick.MarstekBar", category: "app")

    init() {
        host = defaults.string(forKey: "host") ?? ""
        port = defaults.object(forKey: "port") as? Int ?? 30000
        dodPercent = defaults.object(forKey: "dodPercent") as? Double ?? 88
        invertSign = defaults.bool(forKey: "invertSign")
        showMenuBarIcon = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        deviceName = defaults.string(forKey: "deviceName")
        language = AppGroup.language
        status = L10n(AppGroup.language.resolved()).connecting
        payload = Self.restore(from: store)
        NotificationCenter.default.addObserver(forName: .showMenuBarIcon, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showMenuBarIcon = true }
        }
        // The spec has the app start at login; offer it once, the toggle in Settings undoes it.
        if defaults.object(forKey: "didEnableLaunchAtLogin") == nil {
            defaults.set(true, forKey: "didEnableLaunchAtLogin")
            setLaunchAtLogin(true)
        }
        Task { await start() }
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                self?.clock = Date()
            }
        }
    }

    func dashboard(now: Date) -> DashboardModel {
        DashboardModel(payload: payload, now: now, language: language.resolved())
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try enabled ? SMAppService.mainApp.register() : SMAppService.mainApp.unregister()
        } catch {
            log.error("launch at login: \(String(describing: error), privacy: .public)")
            status = text.loginItemFailed
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// payload.json holds only 24 h for the widget; the full 7 days live in history.json.
    private static func restore(from store: PayloadStore) -> WidgetPayload? {
        guard var payload = store.load() else { return nil }
        if var full = store.loadHistory() {
            for sample in payload.history.samples where sample.t > (full.samples.last?.t ?? .distantPast) {
                full.append(sample)
            }
            payload.history = full
        }
        return payload
    }

    var menuBarTitle: String { dashboard(now: clock).menuBarText }

    var menuBarSymbol: String {
        switch payload?.snapshot.soc ?? 0 {
        case ..<13: "battery.0percent"
        case ..<38: "battery.25percent"
        case ..<63: "battery.50percent"
        case ..<88: "battery.75percent"
        default: "battery.100percent"
        }
    }

    func discover() async {
        status = text.searching
        let devices: [DeviceInfo]
        if let poller {
            // Share the poller's socket so discovery never cuts into a poll cycle.
            devices = await poller.discoverDevices()
        } else {
            let transport: UDPSocketTransport
            do { transport = try UDPSocketTransport(broadcast: true) } catch {
                log.error("socket for discovery failed: \(String(describing: error), privacy: .public)")
                status = text.noNetwork
                return
            }
            devices = await MarstekClient.discover(transport: transport, port: UInt16(clamping: port), timeout: .seconds(3))
        }
        log.info("discovery found \(devices.count) device(s): \(devices.compactMap(\.ip).joined(separator: ","), privacy: .public)")
        if let device = devices.first, let ip = device.ip {
            deviceName = device.device
            host = ip
            status = text.found(device.device)
        } else {
            status = text.notFound
        }
    }

    private func start() async {
        guard poller == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }
        if host.isEmpty { await discover() }
        guard !host.isEmpty else { log.error("no host after discovery"); return }
        let transport: UDPSocketTransport
        do { transport = try UDPSocketTransport(broadcast: true) } catch {
            log.error("socket for polling failed: \(String(describing: error), privacy: .public)")
            status = text.noNetwork
            return
        }
        log.info("polling \(self.host, privacy: .public):\(self.port)")
        let poller = Poller(
            settings: settings, transport: transport, initial: payload,
            onUpdate: { [weak self] payload in Task { @MainActor in self?.apply(payload) } },
            onDeviceChange: { [weak self] device in
                Task { @MainActor in
                    guard let self, let ip = device.ip else { return }
                    self.deviceName = device.device ?? self.deviceName
                    self.host = ip
                }
            })
        self.poller = poller
        await poller.start()
    }

    private func apply(_ payload: WidgetPayload) {
        self.payload = payload
        status = ""
        log.debug("payload soc=\(payload.snapshot.soc ?? -1)")
        let now = Date()
        let decision = sync.decide(payload, now: now)
        if decision.write {
            var forWidget = payload
            forWidget.history = payload.history.trimmed(endingAt: now)
            try? store.save(forWidget)
        }
        if lastHistorySave.map({ now.timeIntervalSince($0) >= Self.historySaveInterval }) ?? true {
            lastHistorySave = now
            try? store.saveHistory(payload.history)
        }
        if decision.reload { WidgetCenter.shared.reloadTimelines(ofKind: "MarstekWidget") }
    }

    private var settings: PollerSettings {
        PollerSettings(host: host, port: UInt16(clamping: port), dodPercent: dodPercent,
                       invertSign: invertSign, deviceName: deviceName)
    }

    private func pushSettings() {
        let settings = settings
        if poller == nil, !isStarting, !host.isEmpty {
            Task { await start() }
        } else {
            Task { await poller?.updateSettings(settings) }
        }
    }

    private func save() {
        defaults.set(host, forKey: "host")
        defaults.set(port, forKey: "port")
        defaults.set(dodPercent, forKey: "dodPercent")
        defaults.set(invertSign, forKey: "invertSign")
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(deviceName, forKey: "deviceName")
        defaults.set(language.rawValue, forKey: "language")
    }
}
