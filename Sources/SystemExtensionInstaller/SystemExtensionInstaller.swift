import Domain
import Foundation

/// `CameraExtensionInstaller` の orchestrator 実装。
///
/// SystemExtensions framework には直接依存せず、内側 port
/// (`SystemExtensionActivator`) 経由で動く。Live 配線は
/// `SystemExtensionInstaller+Live.swift` の `live()` で
/// `OSSystemExtensionActivator` を注入する。
///
/// 状態管理：
///
/// - 内部に最後に観測した `CameraExtensionInstallStatus` を保持し、
///   新規 subscriber には initial として emit する。
/// - `activate()` を呼ぶと activator から流れる遷移を内部状態に反映し、
///   全 subscriber に push する。
/// - 進行中の activate request がある間に再度 `activate()` が呼ばれても
///   重複 request は走らない（`isActivating` ガード）。
public actor SystemExtensionInstaller {
    private let activator: any SystemExtensionActivator
    private var lastStatus: CameraExtensionInstallStatus = .notInstalled
    private var continuations: [UUID: AsyncStream<CameraExtensionInstallStatus>.Continuation] = [:]
    private var isActivating = false

    public init(activator: any SystemExtensionActivator) {
        self.activator = activator
    }
}

extension SystemExtensionInstaller: CameraExtensionInstaller {
    public var status: AsyncStream<CameraExtensionInstallStatus> {
        get async {
            AsyncStream { continuation in
                let id = UUID()
                continuation.yield(lastStatus)
                continuations[id] = continuation
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeContinuation(id: id) }
                }
            }
        }
    }

    public func activate() async {
        guard !isActivating else { return }
        guard lastStatus != .installed else { return }
        isActivating = true
        let stream = await activator.activate()
        for await next in stream {
            update(status: next)
        }
        isActivating = false
    }

    public func deactivate() async {
        try? await activator.deactivate()
        update(status: .notInstalled)
    }
}

extension SystemExtensionInstaller {
    private func update(status: CameraExtensionInstallStatus) {
        lastStatus = status
        for continuation in continuations.values {
            continuation.yield(status)
        }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
