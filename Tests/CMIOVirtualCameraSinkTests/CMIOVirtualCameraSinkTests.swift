import Testing
import Foundation
import Domain
import InMemoryFrameTransport
@testable import CMIOVirtualCameraSink

@Suite("CMIOVirtualCameraSink")
struct CMIOVirtualCameraSinkTests {
    private func frame(t: TimeInterval = 0, label: String = "") -> Frame {
        Frame(presentationTime: t, data: Data(label.utf8))
    }

    @Test func send_whenConnected_forwardsToTransport() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let sink = CMIOVirtualCameraSink(transport: transport)
        let f = frame(t: 1, label: "a")
        try await sink.send(f)
        let sent = await transport.sentFrames
        #expect(sent == [f])
    }

    @Test func send_whenNotConnected_autoConnectsAndForwards() async throws {
        let transport = InMemoryFrameTransport()
        let sink = CMIOVirtualCameraSink(transport: transport)
        let f = frame(t: 1, label: "a")
        try await sink.send(f)
        let sent = await transport.sentFrames
        let connected = await transport.isConnected
        #expect(sent == [f])
        #expect(connected)
    }

    @Test func send_multipleFrames_preservesOrder() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let sink = CMIOVirtualCameraSink(transport: transport)
        let f1 = frame(t: 1, label: "a")
        let f2 = frame(t: 2, label: "b")
        let f3 = frame(t: 3, label: "c")
        try await sink.send(f1)
        try await sink.send(f2)
        try await sink.send(f3)
        let sent = await transport.sentFrames
        #expect(sent == [f1, f2, f3])
    }

    @Test func send_afterDisconnect_propagatesDisconnectedDuringSend() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        await transport.disconnect()
        let sink = CMIOVirtualCameraSink(transport: transport)
        await #expect(throws: FrameTransportError.disconnectedDuringSend) {
            try await sink.send(frame(t: 1, label: "a"))
        }
    }

    @Test func send_withFailingConnectTransport_propagatesError() async throws {
        let transport = FailingConnectTransport()
        let sink = CMIOVirtualCameraSink(transport: transport)
        await #expect(throws: FrameTransportError.transport(reason: "connect refused")) {
            try await sink.send(frame(t: 1, label: "a"))
        }
    }
}

private actor FailingConnectTransport: FrameTransport {
    var events: AsyncStream<FrameTransportEvent> {
        AsyncStream { continuation in
            continuation.yield(.disconnected)
            continuation.finish()
        }
    }
    func connect() async throws {
        throw FrameTransportError.transport(reason: "connect refused")
    }
    func disconnect() async {}
    func send(_ frame: Frame) async throws {
        throw FrameTransportError.notConnected
    }
}
