import Testing
import Foundation
import Domain
@testable import InMemoryFrameTransport

@Suite("InMemoryFrameTransport")
struct InMemoryFrameTransportTests {
    private func frame(t: TimeInterval = 0, label: String = "") -> Frame {
        Frame(presentationTime: t, data: Data(label.utf8))
    }

    @Test func init_disconnected_andEmpty() async {
        let transport = InMemoryFrameTransport()
        let connected = await transport.isConnected
        let sent = await transport.sentFrames
        #expect(connected == false)
        #expect(sent.isEmpty)
    }

    @Test func connect_changesStateToConnected() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let connected = await transport.isConnected
        #expect(connected)
    }

    @Test func connect_idempotent() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        try await transport.connect()
        let connected = await transport.isConnected
        #expect(connected)
    }

    @Test func disconnect_changesStateToDisconnected() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        await transport.disconnect()
        let connected = await transport.isConnected
        #expect(connected == false)
    }

    @Test func disconnect_beforeConnect_isNoOp() async {
        let transport = InMemoryFrameTransport()
        await transport.disconnect()
        let connected = await transport.isConnected
        #expect(connected == false)
    }

    @Test func send_beforeConnect_throwsNotConnected() async {
        let transport = InMemoryFrameTransport()
        await #expect(throws: FrameTransportError.notConnected) {
            try await transport.send(frame(t: 1, label: "a"))
        }
    }

    @Test func send_afterDisconnect_throwsNotConnected() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        await transport.disconnect()
        await #expect(throws: FrameTransportError.notConnected) {
            try await transport.send(frame(t: 1, label: "a"))
        }
    }

    @Test func send_oneFrame_roundTrip() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let f = frame(t: 1, label: "hello")
        try await transport.send(f)
        let sent = await transport.sentFrames
        #expect(sent == [f])
    }

    @Test func send_multipleFrames_preservesOrder() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let f1 = frame(t: 1, label: "a")
        let f2 = frame(t: 2, label: "b")
        let f3 = frame(t: 3, label: "c")
        try await transport.send(f1)
        try await transport.send(f2)
        try await transport.send(f3)
        let sent = await transport.sentFrames
        #expect(sent == [f1, f2, f3])
    }

    @Test func events_initialState_isDisconnected() async {
        let transport = InMemoryFrameTransport()
        let stream = await transport.events
        var iter = stream.makeAsyncIterator()
        let first = await iter.next()
        #expect(first == .disconnected)
    }

    @Test func events_afterConnect_emitsConnected() async throws {
        let transport = InMemoryFrameTransport()
        let stream = await transport.events
        var iter = stream.makeAsyncIterator()
        _ = await iter.next()
        try await transport.connect()
        let next = await iter.next()
        #expect(next == .connected)
    }

    @Test func events_afterDisconnect_emitsDisconnected() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let stream = await transport.events
        var iter = stream.makeAsyncIterator()
        _ = await iter.next()
        await transport.disconnect()
        let next = await iter.next()
        #expect(next == .disconnected)
    }

    @Test func events_subscribeAfterConnect_initialIsConnected() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let stream = await transport.events
        var iter = stream.makeAsyncIterator()
        let first = await iter.next()
        #expect(first == .connected)
    }
}
