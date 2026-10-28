import Foundation

/// Every string the widget and the menu panel show, computed from a payload.
/// Views only lay these out, so all wording and rounding is tested here.
public struct DashboardModel: Equatable, Sendable {
    public var socText = "—"
    public var socFraction = 0.0
    public var storedText = "—"
    public var title = "Marstek"
    public var flows = PowerFlows(grid: .idle, home: .idle, socket: .idle)
    public var forecastLabel: String
    public var forecastText = "—"
    public var tempText = "— °C"
    public var todayText: String
    public var chart: [[HistorySample]] = []
    /// The chart's right edge; the time this model describes, not the wall clock.
    public var chartEnd: Date
    public var updatedText = ""
    public var isStale = false
    public var isEmpty = true
    /// Labels for the views, in the chosen language.
    public let text: L10n

    public init(payload: WidgetPayload?, now: Date, calendar: Calendar = .current, language: AppLanguage.Resolved = .uk) {
        let text = L10n(language)
        self.text = text
        forecastLabel = text.idle
        todayText = "\(text.today): —"
        chartEnd = now
        guard let payload else { return }
        let s = payload.snapshot
        isEmpty = false

        if let soc = s.soc, let percent = displayInt(soc, in: 0...100) {
            socText = "\(percent)%"
            socFraction = soc / 100
        }
        if let stored = s.storedWh { storedText = kWhText(stored) }
        let name = (payload.deviceName ?? "Venus").replacingOccurrences(of: "VenusE", with: "Venus E")
        title = [name, s.mode].compactMap { $0 }.joined(separator: " · ")
        flows = PowerFlows.from(s)

        if let stored = s.storedWh, let rated = s.ratedWh, let net = payload.smoothedNetPowerW {
            switch Forecast.estimate(storedWh: stored, ratedWh: rated, netPowerW: net, dodPercent: payload.dodPercent) {
            case .idle: break
            case .untilEmpty(let t):
                forecastLabel = text.lasts
                forecastText = formatDuration(t, language: language)
            case .untilFull(let t):
                forecastLabel = text.untilFull
                forecastText = formatDuration(t, language: language)
            }
        }

        if let temp = s.tempC, let degrees = displayInt(temp, in: -100...150) { tempText = "\(degrees) °C" }
        todayText = "\(text.today): ↑ \(kWhText(payload.today.todayChargedWh)) · ↓ \(kWhText(payload.today.todayDischargedWh))"
        chart = payload.history.series(endingAt: now)

        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        // After a day away a bare time would be ambiguous.
        formatter.dateFormat = calendar.isDate(s.timestamp, inSameDayAs: now) ? "HH:mm" : "dd.MM HH:mm"
        updatedText = "\(text.updated) \(formatter.string(from: s.timestamp))"
        isStale = s.isStale(now: now)
    }
}

extension DashboardModel {
    /// The menu bar has no room for "оновлено"; brackets mark a value that is no longer current.
    public var menuBarText: String {
        guard !isEmpty, socText != "—" else { return "—" }
        return isStale ? "(\(socText))" : socText
    }
}

/// "420 W", or "1.2 kW" from 1000 W. Direction is shown by the diagram, so the sign is dropped.
public func wattsText(_ w: Double) -> String {
    let watts = abs(w)
    guard displayInt(watts, in: 0...10_000_000) != nil else { return "—" }
    if watts >= 1000 { return String(format: "%.1f kW", watts / 1000) }
    return "\(Int(watts.rounded())) W"
}

/// Device values are untrusted: anything non-finite or implausible shows as "—"
/// instead of trapping in `Int(_:)`.
func displayInt(_ value: Double, in range: ClosedRange<Double>) -> Int? {
    guard value.isFinite, range.contains(value) else { return nil }
    return Int(value.rounded())
}

func kWhText(_ wh: Double) -> String { String(format: "%.1f kWh", wh / 1000) }
