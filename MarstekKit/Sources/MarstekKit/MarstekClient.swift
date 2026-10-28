import Foundation

public enum ClientError: Error, Equatable, Sendable {
    case noResponse(method: String)
}

/// Read-only JSON-RPC client with spacing between requests and retries for the
/// device's lossy UDP. Actor isolation alone doesn't stop two callers interleaving
/// across awaits; `Poller` is the single caller and serializes its work.
public actor MarstekClient {
    public private(set) var host: String
    private let port: UInt16
    private let transport: DatagramTransport
    private let minSpacing: Duration
    private let timeout: Duration
    private let attempts: Int
    /// The device ignores ids above 16 bits. A random start keeps a host on the LAN
    /// from guessing which id the next reply needs.
    static let maxID = 65535
    private var nextID: Int
    private var lastSend: ContinuousClock.Instant?

    public init(host: String, port: UInt16 = 30000, transport: DatagramTransport,
                minSpacing: Duration = .seconds(1.5), timeout: Duration = .seconds(3), attempts: Int = 3,
                firstID: Int? = nil) {
        self.host = host
        nextID = firstID ?? Int.random(in: 1...Self.maxID)
        self.port = port
        self.transport = transport
        self.minSpacing = minSpacing
        self.timeout = timeout
        self.attempts = attempts
    }

    public func setHost(_ host: String) { self.host = host }

    public func call<T: Decodable>(_ method: String, as type: T.Type) async throws -> T {
        var issued: Set<Int> = []
        for _ in 0..<attempts {
            if let lastSend { try await Task.sleep(until: lastSend + minSpacing) }
            let id = nextID
            nextID = id >= Self.maxID ? 1 : id + 1
            issued.insert(id)
            try await transport.send(RPC.request(id: id, method: method, params: ["id": 0]), host: host, port: port)
            // Stamped once the datagram is out, so spacing counts from the actual send.
            lastSend = .now
            if let result = try await awaitReply(ids: issued, as: type) { return result }
        }
        throw ClientError.noResponse(method: method)
    }

    /// Waits for a reply to any attempt of the current call (a late answer to an
    /// earlier attempt is still valid data), skipping replies to earlier calls.
    private func awaitReply<T: Decodable>(ids: Set<Int>, as type: T.Type) async throws -> T? {
        let deadline = ContinuousClock.now + timeout
        while true {
            let remaining = deadline - .now
            guard remaining > .zero, let datagram = try await transport.receive(timeout: remaining) else { return nil }
            // Only the battery may answer; anyone else on the network could forge a reply.
            guard datagram.host == host, let id = RPC.peekID(datagram.data), ids.contains(id) else { continue }
            do {
                if let result = try RPC.decode(datagram.data, as: type).result { return result }
            } catch let error as RPCError {
                // A device error (e.g. Method not found) is final: retrying won't change it.
                throw error
            } catch {
                // A garbled reply is no answer; keep waiting, then retry.
            }
        }
    }

    public static let discoveryRequest = RPC.request(id: 0, method: "Marstek.GetDevice", params: ["ble_mac": "0"])

    /// Broadcasts `Marstek.GetDevice` and collects distinct devices until `timeout`.
    public static func discover(transport: DatagramTransport, port: UInt16 = 30000,
                                timeout: Duration) async -> [DeviceInfo] {
        var found: [DeviceInfo] = []
        do {
            try await transport.send(discoveryRequest, host: "255.255.255.255", port: port)
            let deadline = ContinuousClock.now + timeout
            while true {
                let remaining = deadline - .now
                guard remaining > .zero, let datagram = try await transport.receive(timeout: remaining) else { break }
                if datagram.data == discoveryRequest { continue }
                // The first reply can be a Parse error (spec); skip anything that isn't a device.
                guard var info = (try? RPC.decode(datagram.data, as: DeviceInfo.self))?.result,
                      info.device != nil else { continue }
                // Trust where the answer came from, not what it says about itself.
                info.ip = datagram.host
                if !found.contains(where: { $0.ip == info.ip }) { found.append(info) }
            }
        } catch {
            return found
        }
        return found
    }
}
