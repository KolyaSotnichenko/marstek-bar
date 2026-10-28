import Foundation

/// JSON-RPC error returned by the device in place of `result`.
public struct RPCError: Error, Decodable, Equatable, Sendable {
    public let code: Int
    public let message: String
}

public struct RPCReply<T> {
    public let id: Int
    public let src: String?
    public let result: T?
}

public enum RPC {
    public static func request(id: Int, method: String, params: [String: Any]) -> Data {
        let body: [String: Any] = ["id": id, "method": method, "params": params]
        // Only plain JSON values are passed in, so serialization cannot fail.
        return (try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])) ?? Data()
    }

    public static func decode<T: Decodable>(_ data: Data, as: T.Type) throws -> RPCReply<T> {
        let envelope = try decoder.decode(Envelope<T>.self, from: data)
        if let error = envelope.error { throw error }
        return RPCReply(id: envelope.id ?? -1, src: envelope.src, result: envelope.result)
    }

    /// Reads only the `id` so replies can be matched before full decoding.
    public static func peekID(_ data: Data) -> Int? {
        (try? decoder.decode(IDOnly.self, from: data))?.id
    }

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private struct Envelope<T: Decodable>: Decodable {
        let id: Int?
        let src: String?
        let result: T?
        let error: RPCError?
    }

    private struct IDOnly: Decodable { let id: Int? }
}
