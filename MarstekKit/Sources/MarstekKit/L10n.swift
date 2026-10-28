import Foundation

/// The user's language choice. Ukrainian is the default; "system" follows macOS.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case system, uk, en

    public enum Resolved: Sendable, Equatable { case uk, en }

    public func resolved(preferred: [String] = Locale.preferredLanguages) -> Resolved {
        switch self {
        case .uk: .uk
        case .en: .en
        case .system: preferred.first?.hasPrefix("uk") == true ? .uk : .en
        }
    }
}

/// Every user-facing string, in both languages. Views and the app read from here
/// so the widget, the panel and Settings always agree.
public struct L10n: Equatable, Sendable {
    public let language: AppLanguage.Resolved

    public init(_ language: AppLanguage.Resolved) { self.language = language }

    private func pick(_ uk: String, _ en: String) -> String { language == .uk ? uk : en }

    // Dashboard
    public var grid: String { pick("Мережа", "Grid") }
    public var battery: String { pick("Батарея", "Battery") }
    public var home: String { pick("Дім", "Home") }
    public var socket: String { pick("Розетка", "Socket") }
    public var lasts: String { pick("Вистачить на", "Lasts") }
    public var untilFull: String { pick("До повного", "Until full") }
    public var idle: String { pick("Очікування", "Idle") }
    public var today: String { pick("Сьогодні", "Today") }
    public var updated: String { pick("оновлено", "updated") }
    public var chartTitle: String { pick("Заряд за 24 год", "Charge, last 24 h") }
    public var chartStart: String { pick("−24 год", "−24 h") }
    public var chartMiddle: String { pick("−12 год", "−12 h") }
    public var chartNow: String { pick("зараз", "now") }
    var hours: String { pick("год", "h") }
    var minutes: String { pick("хв", "min") }

    // Widget, panel and Settings
    public var widgetDescription: String { pick("Заряд, потужність і прогноз батареї Venus E.", "Charge, power and forecast for a Venus E battery.") }
    public var openAppHint: String { pick("Відкрий MarstekBar, щоб підключитися до батареї", "Open MarstekBar to connect to the battery") }
    public var noData: String { pick("Немає даних", "No data") }
    public var settingsButton: String { pick("Налаштування…", "Settings…") }
    public var quit: String { pick("Вийти", "Quit") }
    public var sectionBattery: String { pick("Батарея", "Battery") }
    public var ipAddress: String { pick("IP-адреса", "IP address") }
    public var findAutomatically: String { pick("Знайти автоматично", "Find automatically") }
    public var port: String { pick("Порт", "Port") }
    public var sectionForecast: String { pick("Прогноз", "Forecast") }
    public func depthOfDischarge(_ percent: Int) -> String {
        pick("Глибина розряду (DOD): \(percent)%", "Depth of discharge (DOD): \(percent)%")
    }
    public var dodHint: String {
        pick("Має збігатися з налаштуванням у застосунку Marstek. Заводське значення 88%.",
             "Should match the setting in the Marstek app. Factory default is 88%.")
    }
    public var invertSign: String { pick("Інвертувати знак потужності", "Invert power sign") }
    public var sectionApp: String { pick("Застосунок", "App") }
    public var showInMenuBar: String { pick("Показувати в рядку меню", "Show in menu bar") }
    public var launchAtLogin: String { pick("Запускати при вході", "Open at login") }
    public var languageLabel: String { pick("Мова", "Language") }
    public func languageName(_ language: AppLanguage) -> String {
        switch language {
        case .system: pick("Системна", "System")
        case .uk: "Українська"
        case .en: "English"
        }
    }

    // Status
    public var connecting: String { pick("Підключення…", "Connecting…") }
    public var searching: String { pick("Пошук батареї…", "Looking for the battery…") }
    public var noNetwork: String { pick("Немає доступу до мережі", "No network access") }
    public func found(_ device: String?) -> String { pick("Знайдено \(device ?? "батарею")", "Found \(device ?? "the battery")") }
    public var notFound: String { pick("Батарею не знайдено. Вкажи IP вручну.", "Battery not found. Enter its IP manually.") }
    public var loginItemFailed: String { pick("Не вдалося змінити автозапуск", "Couldn't change Open at login") }
}
