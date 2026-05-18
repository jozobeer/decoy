import Testing
import Foundation
import Domain
import InMemoryFrameTransport
@testable import CMIOVirtualCameraSink

@Suite("CMIOVirtualCameraSink")
struct CMIOVirtualCameraSinkTests {
    private func frame(t: TimeInterval = 0, payload: UInt8 = 0) -> Frame {
        Frame(presentationTime: t, pixelData: Data(repeating: payload, count: 64), width: 4, height: 4, pixelFormat: 0x42475241, bytesPerRow: 16)
    }

    @Test func send_whenConnected_forwardsToTransport() async throws {
        let transport = InMemoryFrameTransport()
        try await transport.connect()
        let sink = CMIOVirtualCameraSink(transport: transport)
        let f = frame(t: 1, payload: 0xA1)
        try await sink.send(f)
        let sent = await transport.sentFrames
        #expect(sent == [f])
    }

    @Test func send_whenNotConnected_autoConnectsAndForwards() async throws {
        let transport = InMemoryFrameTransport()
        let sink = CMIOVirtualCameraSink(transport: transport)
        let f = frame(t: 1, payload: 0xA1)
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
        let f1 = frame(t: 1, payload: 0xA1)
        let f2 = frame(t: 2, payload: 0xB2)
        let f3 = frame(t: 3, payload: 0xC3)
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
        let f = frame(t: 1, payload: 0xA1)
        await #expect(throws: FrameTransportError.disconnectedDuringSend) {
            try await sink.send(f)
        }
    }

    @Test func send_withFailingConnectTransport_propagatesError() async throws {
        let transport = FailingConnectTransport()
        let sink = CMIOVirtualCameraSink(transport: transport)
        let f = frame(t: 1, payload: 0xA1)
        await #expect(throws: FrameTransportError.transport(reason: "connect refused")) {
            try await sink.send(f)
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
