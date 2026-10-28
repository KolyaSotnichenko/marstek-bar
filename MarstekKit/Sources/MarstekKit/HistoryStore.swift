import Foundation

public struct HistorySample: Codable, Equatable, Sendable {
    public var t: Date
    public var soc: Double

    public init(t: Date, soc: Double) {
        self.t = t
        self.soc = soc
    }
}

/// SOC history for the chart: about one point a minute, kept for 7 days.
public struct HistoryStore: Codable, Equatable, Sendable {
    public internal(set) var samples: [HistorySample] = []

    static let minSpacing: TimeInterval = 55
    static let retention: TimeInterval = 7 * 86400
    static let maxGap: TimeInterval = 300

    public init() {}

    public mutating func append(_ sample: HistorySample) {
        if let last = samples.last, sample.t.timeIntervalSince(last.t) < Self.minSpacing { return }
        samples.append(sample)
        let cutoff = sample.t - Self.retention
        samples.removeAll { $0.t < cutoff }
    }

    /// Samples within `span` before `end`, split into segments wherever the Mac
    /// was off or away (gap over 5 min), so the chart draws a break, not a line.
    public func series(endingAt end: Date, span: TimeInterval = 86400) -> [[HistorySample]] {
        var segments: [[HistorySample]] = []
        for sample in samples where sample.t >= end - span && sample.t <= end {
            if let last = segments.last?.last, sample.t.timeIntervalSince(last.t) <= Self.maxGap {
                segments[segments.count - 1].append(sample)
            } else {
                segments.append([sample])
            }
        }
        return segments
    }
}

extension BatterySnapshot {
    public static let staleAfter: TimeInterval = 300

    public func isStale(now: Date) -> Bool {
        now.timeIntervalSince(timestamp) > Self.staleAfter
    }
}
