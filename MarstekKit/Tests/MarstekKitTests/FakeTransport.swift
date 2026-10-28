import Foundation
@testable import MarstekKit

/// Scripted transport: `responder` decides which datagrams arrive after each send.
/// `receive` returns queued datagrams immediately and `nil` (timeout) when empty.
actor FakeTransport: DatagramTransport {
    struct Sent { let id: Int; let method: String; let host: String; let at: ContinuousClock.Instant }

    typealias Responder = @Sendable (_ id: Int, _ method: String, _ host: String) -> [Data]

    private var responder: Responder
    private(set) var sent: [Sent] = []
    private var inbox: [(data: Data, host: String)] = []

    init(responder: @escaping Responder) { self.responder = responder }

    func setResponder(_ responder: @escaping Responder) { self.responder = responder }

    func send(_ data: Data, host: String, port: UInt16) async throws {
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let id = obj["id"] as? Int ?? -1
        let method = obj["method"] as? String ?? ""
        sent.append(Sent(id: id, method: method, host: host, at: .now))
        for reply in responder(id, method, host) { inbox.append((reply, Self.sender(of: reply, sentTo: host))) }
    }

    /// A broadcast is answered from each device's own address, which a device
    /// reply carries in `result.ip`.
    private static func sender(of reply: Data, sentTo host: String) -> String {
        guard host == "255.255.255.255",
              let obj = (try? JSONSerialization.jsonObject(with: reply)) as? [String: Any],
              let ip = (obj["result"] as? [String: Any])?["ip"] as? String else { return host }
        return ip
    }

    /// Lets a test deliver a datagram that is not a reply to a send (e.g. a broadcast echo).
    func inject(_ data: Data, host: String) { inbox.append((data, host)) }

    func receive(timeout: Duration) async throws -> (data: Data, host: String)? {
        inbox.isEmpty ? nil : inbox.removeFirst()
    }
}

/// Builds a device reply with the given id and result body.
func reply(id: Int, _ result: String) -> Data {
    Data(#"{"id":\#(id),"src":"VenusE 3.0-a1b2c3d4e5f6","result":\#(result)}"#.utf8)
}

let batResult = #"{"id":0,"soc":64,"bat_temp":25.0,"bat_capacity":3276.8,"rated_capacity":5120.0}"#
let esResult = #"{"id":0,"bat_soc":64,"bat_cap":5120,"ongrid_power":-420,"offgrid_power":0,"total_grid_output_energy":3473,"total_grid_input_energy":9893}"#
