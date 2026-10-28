import Foundation
import MarstekKit

/// Shared storage between the menu bar app and the widget.
enum AppGroup {
    static var id: String {
        Bundle.main.object(forInfoDictionaryKey: "AppGroupID") as? String ?? "com.nick.marstek"
    }

    static var directory: URL {
        if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: id) { return url }
        // Unsigned builds have no group container; keep working from Application Support.
        let fallback = URL.applicationSupportDirectory.appendingPathComponent("MarstekBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        return fallback
    }

    static var store: PayloadStore { PayloadStore(directory: directory) }

    /// Ukrainian unless the user picked otherwise in Settings.
    static var language: AppLanguage {
        defaults.string(forKey: "language").flatMap(AppLanguage.init(rawValue:)) ?? .uk
    }
    static var defaults: UserDefaults { UserDefaults(suiteName: id) ?? .standard }
}

extension WidgetPayload {
    /// The mockup's discharge example, for widget placeholders and previews.
    static var preview: WidgetPayload {
        let now = Date()
        var snapshot = BatterySnapshot.normalize(es: nil, bat: nil, mode: "Manual", invertSign: false, at: now)
        snapshot.soc = 64
        snapshot.storedWh = 3276.8
        snapshot.ratedWh = 5120
        snapshot.tempC = 27
        snapshot.gridPowerW = -420
        snapshot.socketPowerW = 0
        var history = HistoryStore()
        for minute in stride(from: 24 * 60, through: 0, by: -10) {
            let t = now.addingTimeInterval(-Double(minute) * 60)
            history.append(HistorySample(t: t, soc: 64 + 30 * sin(Double(minute) / 300)))
        }
        return WidgetPayload(snapshot: snapshot, smoothedNetPowerW: -420, today: DailyCounters(),
                             history: history, dodPercent: 88, deviceName: "VenusE 3.0")
    }
}
