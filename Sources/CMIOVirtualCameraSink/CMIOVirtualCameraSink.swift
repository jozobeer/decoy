import Domain
import Foundation

public enum CMIOVirtualCameraSinkError: Error, Equatable, LocalizedError, Sendable {
    case cameraExtensionUnavailable(CameraExtensionInstallStatus)

    public var errorDescription: String? {
        switch self {
        case .cameraExtensionUnavailable(.notInstalled):
            return "Camera Extension がまだインストールされていません"
        case .cameraExtensionUnavailable(.installing):
            return "Camera Extension をインストール中です"
        case .cameraExtensionUnavailable(.needsApproval):
            return "System Settings で Camera Extension の承認が必要です"
        case .cameraExtensionUnavailable(.installed):
            return "Camera Extension は利用可能です"
        }
    }
}

/// `VirtualCameraSink` の本番実装 ― `FrameTransport` (#43) 経由で
/// Camera Extension に frame を送る adapter。
///
/// 役割：
///
/// - `init(transport:)` で IPC 層 (`FrameTransport`) を注入される。
///   live wiring では Mach port + IOSurface 実装、テストでは
///   `InMemoryFrameTransport` を渡す。
/// - `send(_:)` で frame を transport に push する。transport が
///   throw した場合はそのまま伝播 ― `Broadcaster` の `.sendFailed`
///   event 経路に乗る。
/// - 初回 `send(_:)` のタイミングで遅延 connect ― `init` 内では IPC
///   接続を張らない (init は同期、connect は async なので必然)。
///
/// 契約：
///
/// - `send(_:)` を複数回呼んでも、接続済みなら都度 `connect()` は
///   走らない (transport 側で idempotent)。
/// - transport が `.notConnected` を返した場合は本 adapter で
///   自動的に `connect()` を試みる ― caller が接続を意識せず
///   `VirtualCameraSink` として使えるようにする。
/// - `connect()` 自体が失敗した場合はそのエラーを伝播する。
public actor CMIOVirtualCameraSink {
    private let transport: any FrameTransport
    private let installer: (any CameraExtensionInstaller)?
    private var installStatus: CameraExtensionInstallStatus?
    private var statusTask: Task<Void, Never>?
    private var statusWaiters: [CheckedContinuation<CameraExtensionInstallStatus, Never>] = []

    public init(
        transport: any FrameTransport,
        installer: (any CameraExtensionInstaller)? = nil
    ) {
        self.transport = transport
        self.installer = installer
    }

    deinit {
        statusTask?.cancel()
    }
}

extension CMIOVirtualCameraSink: VirtualCameraSink {
    public func send(_ frame: Frame) async throws {
        try await ensureCameraExtensionAvailable()
        do {
            try await transport.send(frame)
        } catch FrameTransportError.notConnected {
            try await transport.connect()
            try await transport.send(frame)
        }
    }
}

private extension CMIOVirtualCameraSink {
    func ensureCameraExtensionAvailable() async throws {
        guard installer != nil else { return }
        let status = await currentInstallStatus()
        guard status == .installed else {
            throw CMIOVirtualCameraSinkError.cameraExtensionUnavailable(status)
        }
    }

    func currentInstallStatus() async -> CameraExtensionInstallStatus {
        startStatusMonitorIfNeeded()
        if let installStatus { return installStatus }
        return await withCheckedContinuation { continuation in
            statusWaiters.append(continuation)
        }
    }

    func startStatusMonitorIfNeeded() {
        guard statusTask == nil, let installer else { return }
        statusTask = Task { [weak self, installer] in
            for await status in await installer.status {
                await self?.applyInstallStatus(status)
            }
            await self?.finishStatusMonitor()
        }
    }

    func applyInstallStatus(_ status: CameraExtensionInstallStatus) async {
        installStatus = status
        resumeStatusWaiters(with: status)
        guard status != .installed else { return }
        await transport.disconnect()
    }

    func finishStatusMonitor() {
        resumeStatusWaiters(with: installStatus ?? .notInstalled)
    }

    func resumeStatusWaiters(with status: CameraExtensionInstallStatus) {
        let waiters = statusWaiters
        statusWaiters.removeAll()
        waiters.forEach { $0.resume(returning: status) }
    }
}
