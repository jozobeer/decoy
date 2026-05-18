import ConcurrencyExtras
import Domain
import Foundation
import Testing
@testable import MachPortFrameTransport

/// `MachPortFrameTransport` の actor + state machine 部分 (Mach OS API
/// は呼ばない) を、in-memory な `MachPortLookup` / `MachPortSender`
/// fake を注入して検証する。+Live.swift 側 (実 Mach 呼び出し) は
/// codecov ignore なので本テストでは触れない。
@Suite("MachPortFrameTransport", .timeLimit(.minutes(1)))
struct MachPortFrameTransportTests {

    private static func frame(_ pts: TimeInterval = 0.0, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(
            presentationTime: pts,
            pixelData: Data(repeating: byte, count: 64),
            width: 4,
            height: 4,
            pixelFormat: 0x42475241,
            bytesPerRow: 16
        )
    }

    @Test
    func eventsStream_emitsDisconnectedInitially() async {
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 42)),
            sender: RecordingSender()
        )
        var iterator = await transport.events.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .disconnected)
    }

    @Test
    func connect_resolvesPortAndBroadcastsConnected() async throws {
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 42)),
            sender: RecordingSender()
        )
        var iterator = await transport.events.makeAsyncIterator()
        _ = await iterator.next() // .disconnected

        try await transport.connect()

        let observed = await iterator.next()
        #expect(observed == .connected)
    }

    @Test
    func connect_whenAlreadyConnected_isNoop() async throws {
        let lookup = SuccessLookup(token: MachPortToken(raw: 42))
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: lookup,
            sender: RecordingSender()
        )
        try await transport.connect()
        try await transport.connect()
        #expect(await lookup.callCount == 1)
    }

    @Test
    func connect_whenLookupFails_throwsTransportAndBroadcastsSendFailed() async {
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: FailingLookup(),
            sender: RecordingSender()
        )
        var iterator = await transport.events.makeAsyncIterator()
        _ = await iterator.next() // .disconnected

        await #expect(throws: FrameTransportError.self) {
            try await transport.connect()
        }
        let observed = await iterator.next()
        guard case .sendFailed = observed else {
            Issue.record("expected .sendFailed, got \(String(describing: observed))")
            return
        }
    }

    @Test
    func send_whenNotConnected_throwsNotConnected() async {
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 42)),
            sender: RecordingSender()
        )
        await #expect(throws: FrameTransportError.notConnected) {
            try await transport.send(Self.frame())
        }
    }

    @Test
    func send_whenConnected_forwardsToSender() async throws {
        let sender = RecordingSender()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 7)),
            sender: sender
        )
        try await transport.connect()
        try await transport.send(Self.frame(0.5))

        let sent = await sender.sentFrames
        #expect(sent.count == 1)
        #expect(sent.first?.frame.presentationTime == 0.5)
        #expect(sent.first?.port == MachPortToken(raw: 7))
    }

    @Test
    func send_whenSenderFails_throwsTransportAndBroadcastsSendFailed() async throws {
        let sender = FailingSender()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 7)),
            sender: sender
        )
        try await transport.connect()
        var iterator = await transport.events.makeAsyncIterator()
        _ = await iterator.next() // .connected (replay of last)

        await #expect(throws: FrameTransportError.self) {
            try await transport.send(Self.frame())
        }
        let observed = await iterator.next()
        guard case .sendFailed = observed else {
            Issue.record("expected .sendFailed, got \(String(describing: observed))")
            return
        }
    }

    @Test
    func disconnect_releasesPortAndBroadcastsDisconnected() async throws {
        let sender = RecordingSender()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 7)),
            sender: sender
        )
        try await transport.connect()
        var iterator = await transport.events.makeAsyncIterator()
        _ = await iterator.next() // .connected (replay)

        await transport.disconnect()

        let observed = await iterator.next()
        #expect(observed == .disconnected)
        let released = await sender.releasedPorts
        #expect(released == [MachPortToken(raw: 7)])
    }

    @Test
    func disconnect_whenNotConnected_isNoop() async {
        let sender = RecordingSender()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 7)),
            sender: sender
        )
        await transport.disconnect()
        let released = await sender.releasedPorts
        #expect(released.isEmpty)
    }

    @Test
    func eventsStream_replaysLastEventToNewSubscribers() async throws {
        let transport = MachPortFrameTransport(
            serviceName: "decoy.test",
            lookup: SuccessLookup(token: MachPortToken(raw: 7)),
            sender: RecordingSender()
        )
        try await transport.connect()

        var iterator = await transport.events.makeAsyncIterator()
        let replayed = await iterator.next()
        #expect(replayed == .connected)
    }
}

// MARK: - Fakes

private actor SuccessLookup: MachPortLookup {
    private let token: MachPortToken
    private(set) var callCount: Int = 0

    init(token: MachPortToken) {
        self.token = token
    }

    func lookUp(serviceName: String) async throws -> MachPortToken {
        callCount += 1
        return token
    }
}

private struct FailingLookup: MachPortLookup {
    func lookUp(serviceName: String) async throws -> MachPortToken {
        throw MachPortTransportError.lookupFailed(serviceName: serviceName, code: -1)
    }
}

private actor RecordingSender: MachPortSender {
    struct SentRecord: Sendable, Equatable {
        let frame: Frame
        let port: MachPortToken
    }

    private(set) var sentFrames: [SentRecord] = []
    private(set) var releasedPorts: [MachPortToken] = []

    func send(frame: Frame, via port: MachPortToken) async throws {
        sentFrames.append(SentRecord(frame: frame, port: port))
    }

    func release(port: MachPortToken) async {
        releasedPorts.append(port)
    }
}

private struct FailingSender: MachPortSender {
    func send(frame: Frame, via port: MachPortToken) async throws {
        throw MachPortTransportError.sendFailed(code: -42)
    }
    func release(port: MachPortToken) async {}
}
