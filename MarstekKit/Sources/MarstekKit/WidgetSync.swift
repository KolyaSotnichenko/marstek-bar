import Foundation

extension DashboardModel {
    /// What the widget visibly shows, minus "оновлено ГГ:ХХ": a reload is only
    /// worth WidgetKit's daily budget when this changes.
    public struct Signature: Equatable, Sendable {
        let texts: [String]
        let isStale: Bool
    }

    public var signature: Signature {
        func flow(_ f: FlowState) -> String {
            if case .active(let w) = f { return wattsText(w) }
            return "-"
        }
        return Signature(texts: [socText, storedText, title, flow(flows.grid), flow(flows.home), flow(flows.socket),
                                 forecastLabel, forecastText, tempText, todayText],
                         isStale: isStale)
    }
}

/// Decides when the app writes the payload and asks WidgetKit to reload.
/// Writing every 15 s poll rewrote hundreds of KB each time, and reloading on
/// every poll would exhaust the widget's daily refresh budget.
public struct WidgetSync: Sendable {
    public static let minWriteInterval: TimeInterval = 60
    public static let minReloadInterval: TimeInterval = 300

    public struct Decision: Equatable, Sendable {
        public let write: Bool
        public let reload: Bool

        public init(write: Bool, reload: Bool) {
            self.write = write
            self.reload = reload
        }
    }

    private var lastSignature: DashboardModel.Signature?
    private var lastWrite: Date?
    private var lastReload: Date?
    private var reloadPending = false

    public init() {}

    public mutating func decide(_ payload: WidgetPayload, now: Date, calendar: Calendar = .current) -> Decision {
        let signature = DashboardModel(payload: payload, now: now, calendar: calendar).signature
        let changed = signature != lastSignature
        lastSignature = signature
        reloadPending = reloadPending || changed

        let reload = reloadPending && lastReload.map { now.timeIntervalSince($0) >= Self.minReloadInterval } ?? true
        // The widget must read what it is told to show, and history grows each minute.
        let write = changed || reload || lastWrite.map { now.timeIntervalSince($0) >= Self.minWriteInterval } ?? true

        if write { lastWrite = now }
        if reload {
            lastReload = now
            reloadPending = false
        }
        return Decision(write: write, reload: reload)
    }
}

extension HistoryStore {
    /// The widget only draws 24 h; the full 7 days stay in their own file.
    public func trimmed(endingAt end: Date, span: TimeInterval = 86400) -> HistoryStore {
        var copy = self
        copy.samples.removeAll { $0.t < end - span }
        return copy
    }
}
