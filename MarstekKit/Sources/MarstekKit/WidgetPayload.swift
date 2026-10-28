import Foundation

/// Everything the widget needs, written by the app into the App Group container.
public struct WidgetPayload: Codable, Equatable, Sendable {
    public var snapshot: BatterySnapshot
    public var smoothedNetPowerW: Double?
    public var today: DailyCounters
    public var history: HistoryStore
    public var dodPercent: Double
    public var deviceName: String?

    public init(snapshot: BatterySnapshot, smoothedNetPowerW: Double?, today: DailyCounters,
                history: HistoryStore, dodPercent: Double, deviceName: String?) {
        self.snapshot = snapshot
        self.smoothedNetPowerW = smoothedNetPowerW
        self.today = today
        self.history = history
        self.dodPercent = dodPercent
        self.deviceName = deviceName
    }
}

public struct PayloadStore: Sendable {
    public let url: URL
    /// Full 7-day history; only the app reads it, so it is written rarely.
    public let historyURL: URL

    public init(directory: URL) {
        url = directory.appendingPathComponent("payload.json")
        historyURL = directory.appendingPathComponent("history.json")
    }

    public func save(_ payload: WidgetPayload) throws { try write(payload, to: url) }
    public func load() -> WidgetPayload? { read(WidgetPayload.self, from: url) }
    public func saveHistory(_ history: HistoryStore) throws { try write(history, to: historyURL) }
    public func loadHistory() -> HistoryStore? { read(HistoryStore.self, from: historyURL) }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func read<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(type, from: data)
    }
}
