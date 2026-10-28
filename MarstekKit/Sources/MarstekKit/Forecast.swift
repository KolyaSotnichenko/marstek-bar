import Foundation

/// Exponential moving average over irregular samples, so the forecast doesn't
/// jump with every kettle. A change of direction restarts it.
public struct PowerSmoother: Codable, Equatable, Sendable {
    public let timeConstant: TimeInterval
    public private(set) var value: Double?
    private var lastAt: Date?

    public init(timeConstant: TimeInterval = 300) { self.timeConstant = timeConstant }

    public mutating func add(_ watts: Double, at date: Date) -> Double {
        guard let current = value, let lastAt, current * watts > 0 else {
            value = watts
            self.lastAt = date
            return watts
        }
        let dt = max(0, date.timeIntervalSince(lastAt))
        let alpha = 1 - exp(-dt / timeConstant)
        let next = current + alpha * (watts - current)
        value = next
        self.lastAt = date
        return next
    }
}

public enum ForecastResult: Equatable, Sendable {
    case idle
    case untilEmpty(TimeInterval)
    case untilFull(TimeInterval)
}

public enum Forecast {
    /// The reserve below DOD is never counted as usable.
    public static func estimate(storedWh: Double, ratedWh: Double, netPowerW: Double, dodPercent: Double) -> ForecastResult {
        guard abs(netPowerW) >= idleThresholdW else { return .idle }
        if netPowerW < 0 {
            let reserveWh = ratedWh * (1 - dodPercent / 100)
            return .untilEmpty(max(0, storedWh - reserveWh) / -netPowerW * 3600)
        }
        return .untilFull(max(0, ratedWh - storedWh) / netPowerW * 3600)
    }
}

/// "≈ 6 год 20 хв" / "≈ 6 h 20 min", rounded to 5 minutes.
public func formatDuration(_ t: TimeInterval, language: AppLanguage.Resolved = .uk) -> String {
    let l = L10n(language)
    if t.isNaN { return "—" }
    if t < 5 * 60 { return "< 5 \(l.minutes)" }
    if t >= 100 * 3600 { return "> 99 \(l.hours)" }
    let minutes = Int((t / 60 / 5).rounded()) * 5
    let hours = minutes / 60, rest = minutes % 60
    if hours == 0 { return "≈ \(rest) \(l.minutes)" }
    if rest == 0 { return "≈ \(hours) \(l.hours)" }
    return "≈ \(hours) \(l.hours) \(rest) \(l.minutes)"
}
