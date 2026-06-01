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

    @Test func send_whenInstallerIsNotInstalled_throwsBeforeConnectingTransport() async throws {
        let transport = InMemoryFrameTransport()
        let installer = MutableCameraExtensionInstaller(status: .notInstalled)
        let sink = CMIOVirtualCameraSink(transport: transport, installer: installer)

        await #expect(throws: CMIOVirtualCameraSinkError.cameraExtensionUnavailable(.notInstalled)) {
            try await sink.send(frame(t: 1, payload: 0xA1))
        }

        let sent = await transport.sentFrames
        let connected = await transport.isConnected
        #expect(sent.isEmpty)
        #expect(!connected)
    }

    @Test func send_whenInstallerIsInstalled_connectsAndForwards() async throws {
        let transport = InMemoryFrameTransport()
        let installer = MutableCameraExtensionInstaller(status: .installed)
        let sink = CMIOVirtualCameraSink(transport: transport, installer: installer)
        let f = frame(t: 1, payload: 0xA1)

        try await sink.send(f)

        let sent = await transport.sentFrames
        let connected = await transport.isConnected
        #expect(sent == [f])
        #expect(connected)
    }

    @Test func statusChangeAwayFromInstalled_disconnectsTransportAndBlocksSend() async throws {
        let transport = InMemoryFrameTransport()
        let installer = MutableCameraExtensionInstaller(status: .installed)
        let sink = CMIOVirtualCameraSink(transport: transport, installer: installer)
        let first = frame(t: 1, payload: 0xA1)

        try await sink.send(first)
        await installer.set(.needsApproval)
        try await eventually { !(await transport.isConnected) }

        await #expect(throws: CMIOVirtualCameraSinkError.cameraExtensionUnavailable(.needsApproval)) {
            try await sink.send(frame(t: 2, payload: 0xB2))
        }

        let sent = await transport.sentFrames
        #expect(sent == [first])
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

private actor MutableCameraExtensionInstaller: CameraExtensionInstaller {
    private var currentStatus: CameraExtensionInstallStatus
    private var continuations: [UUID: AsyncStream<CameraExtensionInstallStatus>.Continuation] = [:]

    init(status: CameraExtensionInstallStatus) {
        currentStatus = status
    }

    var status: AsyncStream<CameraExtensionInstallStatus> {
        AsyncStream { continuation in
            let id = UUID()
            continuation.yield(currentStatus)
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    func activate() async {}

    func deactivate() async {
        set(.notInstalled)
    }

    func set(_ status: CameraExtensionInstallStatus) {
        currentStatus = status
        continuations.values.forEach { $0.yield(status) }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

private func eventually(
    _ predicate: @escaping @Sendable () async -> Bool
) async throws {
    for _ in 0..<100 {
        if await predicate() { return }
        try await Task.sleep(nanoseconds: 1_000_000)
    }
    Issue.record("condition was not met")
}
