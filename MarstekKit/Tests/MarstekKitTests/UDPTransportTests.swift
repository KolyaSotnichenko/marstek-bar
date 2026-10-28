import Foundation
import Testing
@testable import MarstekKit

@Suite struct UDPTransportTests {
    /// poll() treats a negative timeout as "wait forever"; an elapsed deadline must return at once.
    @Test(.timeLimit(.minutes(1))) func negativeTimeoutReturnsImmediately() async throws {
        let transport = try UDPSocketTransport()
        let started = ContinuousClock.now
        let result = try await transport.receive(timeout: .milliseconds(-5))
        #expect(result == nil)
        #expect(started.duration(to: .now) < .seconds(1))
    }
}
