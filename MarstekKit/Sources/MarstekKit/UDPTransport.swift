import Darwin
import Foundation

public protocol DatagramTransport: Sendable {
    func send(_ data: Data, host: String, port: UInt16) async throws
    /// Returns `nil` when nothing arrives within `timeout`.
    func receive(timeout: Duration) async throws -> (data: Data, host: String)?
}

public struct SocketError: Error, Equatable, Sendable {
    public let call: String
    public let code: Int32
}

/// IPv4 UDP socket on BSD sockets. Blocking calls run on a private serial queue
/// so they never occupy Swift's cooperative thread pool.
public final class UDPSocketTransport: DatagramTransport, @unchecked Sendable {
    private let fd: Int32
    private let queue = DispatchQueue(label: "marstek.udp")

    public init(bindPort: UInt16? = nil, broadcast: Bool = false) throws {
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw SocketError(call: "socket", code: errno) }
        var on: Int32 = 1
        let size = socklen_t(MemoryLayout<Int32>.size)
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, size)
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &on, size)
        if broadcast { setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &on, size) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = (bindPort ?? 0).bigEndian
        addr.sin_addr.s_addr = INADDR_ANY
        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw SocketError(call: "bind", code: code)
        }
    }

    deinit { close(fd) }

    public func send(_ data: Data, host: String, port: UInt16) async throws {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else {
            throw SocketError(call: "inet_pton", code: EINVAL)
        }
        let sent = data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { throw SocketError(call: "sendto", code: errno) }
    }

    public func receive(timeout: Duration) async throws -> (data: Data, host: String)? {
        let (seconds, attoseconds) = timeout.components
        // poll() waits forever on a negative timeout; an elapsed deadline means "don't wait".
        let millis = max(0, Int32(clamping: seconds * 1000 + attoseconds / 1_000_000_000_000_000))
        let fd = self.fd
        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                let ready = poll(&pfd, 1, millis)
                if ready == 0 { return continuation.resume(returning: nil) }
                guard ready > 0 else {
                    return continuation.resume(throwing: SocketError(call: "poll", code: errno))
                }
                var buffer = [UInt8](repeating: 0, count: 8192)
                var from = sockaddr_in()
                var fromLen = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = withUnsafeMutablePointer(to: &from) {
                    $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                        recvfrom(fd, &buffer, buffer.count, 0, $0, &fromLen)
                    }
                }
                guard count >= 0 else {
                    return continuation.resume(throwing: SocketError(call: "recvfrom", code: errno))
                }
                var text = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                inet_ntop(AF_INET, &from.sin_addr, &text, socklen_t(INET_ADDRSTRLEN))
                let host = String(decoding: text.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                continuation.resume(returning: (Data(buffer.prefix(count)), host))
            }
        }
    }
}
