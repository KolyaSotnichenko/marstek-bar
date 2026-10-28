import Foundation
import Testing
@testable import MarstekKit

@Suite struct ClientTests {
    func client(_ transport: FakeTransport, spacing: Duration = .zero) -> MarstekClient {
        MarstekClient(host: "192.168.1.50", transport: transport, minSpacing: spacing, timeout: .milliseconds(50))
    }

    @Test func retriesThenSucceeds() async throws {
        let calls = Counter()
        let transport = FakeTransport { id, _, _ in
            calls.increment() == 1 ? [] : [reply(id: id, batResult)]
        }
        let bat = try await client(transport).call("Bat.GetStatus", as: BatStatus.self)
        #expect(bat.batTemp == 25.0)
        #expect(await transport.sent.count == 2)
    }

    @Test func throwsAfterThreeAttempts() async throws {
        let transport = FakeTransport { _, _, _ in [] }
        await #expect(throws: ClientError.noResponse(method: "Bat.GetStatus")) {
            try await client(transport).call("Bat.GetStatus", as: BatStatus.self)
        }
        #expect(await transport.sent.count == 3)
    }

    @Test func ignoresStaleID() async throws {
        let stale = #"{"id":0,"soc":11}"#
        let transport = FakeTransport { id, _, _ in [reply(id: id - 1, stale), reply(id: id, batResult)] }
        let bat = try await client(transport).call("Bat.GetStatus", as: BatStatus.self)
        #expect(bat.soc == 64)
    }

    @Test func acceptsLateReplyToEarlierAttemptOfSameCall() async throws {
        let firstID = Counter()
        let transport = FakeTransport { id, _, _ in
            // Attempt 1 gets nothing; its reply only shows up during attempt 2.
            firstID.increment() == 1 ? [] : [reply(id: id - 1, batResult)]
        }
        let bat = try await client(transport).call("Bat.GetStatus", as: BatStatus.self)
        #expect(bat.batTemp == 25.0)
        #expect(await transport.sent.count == 2)
    }

    @Test func garbledReplyIsRetried() async throws {
        let calls = Counter()
        let transport = FakeTransport { id, _, _ in
            calls.increment() == 1 ? [reply(id: id, #"{"bat_temp":"hot"}"#)] : [reply(id: id, batResult)]
        }
        let bat = try await client(transport).call("Bat.GetStatus", as: BatStatus.self)
        #expect(bat.soc == 64)
    }

    @Test func doesNotRetryDeviceError() async throws {
        let transport = FakeTransport { id, _, _ in
            [Data(#"{"id":\#(id),"error":{"code":-32601,"message":"Method not found"}}"#.utf8)]
        }
        await #expect(throws: RPCError.self) { try await client(transport).call("PV.GetStatus", as: ESStatus.self) }
        #expect(await transport.sent.count == 1)
    }

    @Test func spacesRequests() async throws {
        let transport = FakeTransport { id, _, _ in [reply(id: id, batResult)] }
        let c = client(transport, spacing: .milliseconds(200))
        _ = try await c.call("Bat.GetStatus", as: BatStatus.self)
        _ = try await c.call("Bat.GetStatus", as: BatStatus.self)
        let sent = await transport.sent
        #expect(sent.count == 2)
        #expect(sent[0].at.duration(to: sent[1].at) >= .milliseconds(200))
    }

    @Test func sendsToCurrentHost() async throws {
        let transport = FakeTransport { id, _, _ in [reply(id: id, batResult)] }
        let c = client(transport)
        await c.setHost("192.168.1.51")
        _ = try await c.call("Bat.GetStatus", as: BatStatus.self)
        #expect(await transport.sent.first?.host == "192.168.1.51")
    }

    @Test func discoverIgnoresNonDevices() async {
        let transport = FakeTransport { _, _, _ in [] }
        await transport.inject(Data(#"{"id":0,"result":{}}"#.utf8), host: "192.168.1.60")
        #expect(await MarstekClient.discover(transport: transport, timeout: .milliseconds(50)).isEmpty)
    }

    @Test func discoverUsesSenderAddress() async throws {
        let transport = FakeTransport { _, _, _ in [] }
        await transport.inject(Data(#"{"id":0,"result":{"device":"VenusE 3.0","ip":"10.0.0.99"}}"#.utf8), host: "192.168.1.50")
        let found = await MarstekClient.discover(transport: transport, timeout: .milliseconds(50))
        #expect(found.map(\.ip) == ["192.168.1.50"])
    }

    @Test func discoverSkipsEchoAndParsesDevice() async throws {
        let device = try fixture("get_device")
        let parseError = Data(#"{"id":0,"src":"VenusE 3.0-a1b2c3d4e5f6","error":{"code":-32700,"message":"Parse error"}}"#.utf8)
        let transport = FakeTransport { _, _, _ in [MarstekClient.discoveryRequest, parseError, device, device] }
        let found = await MarstekClient.discover(transport: transport, timeout: .milliseconds(50))
        #expect(found.count == 1)
        #expect(found.first?.ip == "192.168.1.50")
        #expect(await transport.sent.first?.host == "255.255.255.255")
    }
}

/// Thread-safe call counter for responders.
final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0
    func increment() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
}
