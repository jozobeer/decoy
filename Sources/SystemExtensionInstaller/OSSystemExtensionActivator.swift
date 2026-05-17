import Domain
import SystemExtensions

/// `SystemExtensionActivator` の live 実装。`OSSystemExtensionRequest`
/// （SystemExtensions framework）に対して activation / deactivation 要求を
/// 出し、delegate コールバックを `CameraExtensionInstallStatus` に翻訳する。
///
/// `OSSystemExtensionRequest.delegate` は `OSSystemExtensionRequestDelegate`
/// を要求 ― AnyObject クラス制約があるため Swift actor では満たせない。
/// そのため内部で `RequestDelegate` (NSObject) を生成して delegate に据え、
/// 結果を `AsyncStream` に橋渡しする。
///
/// Coverage note: SystemExtensions framework は実 .app bundle + signed
/// 環境でしか動かない。orchestrator のテストは `SystemExtensionInstaller`
/// 側で `FakeSystemExtensionActivator` を使う。この file は live wiring の
/// みなので coverage 除外 (`codecov.yml` ignore 済み)。
public struct OSSystemExtensionActivator: Sendable {
    private let bundleIdentifier: String

    public init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }
}

extension OSSystemExtensionActivator: SystemExtensionActivator {
    public func activate() -> AsyncStream<CameraExtensionInstallStatus> {
        AsyncStream { continuation in
            continuation.yield(.installing)
            let request = OSSystemExtensionRequest.activationRequest(
                forExtensionWithIdentifier: bundleIdentifier,
                queue: .main
            )
            let delegate = RequestDelegate(continuation: continuation)
            request.delegate = delegate
            continuation.onTermination = { _ in _ = delegate }
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }

    public func deactivate() async throws {
        let request = OSSystemExtensionRequest.deactivationRequest(
            forExtensionWithIdentifier: bundleIdentifier,
            queue: .main
        )
        let _: Void = try await withCheckedThrowingContinuation { continuation in
            let delegate = DeactivationDelegate(continuation: continuation)
            request.delegate = delegate
            objc_setAssociatedObject(request, "delegate-ref", delegate, .OBJC_ASSOCIATION_RETAIN)
            OSSystemExtensionManager.shared.submitRequest(request)
        }
    }
}

private final class RequestDelegate: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    private let continuation: AsyncStream<CameraExtensionInstallStatus>.Continuation

    init(continuation: AsyncStream<CameraExtensionInstallStatus>.Continuation) {
        self.continuation = continuation
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {
        continuation.yield(.needsApproval)
    }

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        continuation.yield(result == .completed ? .installed : .needsApproval)
        continuation.finish()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        continuation.yield(.notInstalled)
        continuation.finish()
    }
}

private final class DeactivationDelegate: NSObject, OSSystemExtensionRequestDelegate, @unchecked Sendable {
    private let continuation: CheckedContinuation<Void, Error>

    init(continuation: CheckedContinuation<Void, Error>) {
        self.continuation = continuation
    }

    func request(_ request: OSSystemExtensionRequest, actionForReplacingExtension existing: OSSystemExtensionProperties, withExtension ext: OSSystemExtensionProperties) -> OSSystemExtensionRequest.ReplacementAction {
        .replace
    }

    func requestNeedsUserApproval(_ request: OSSystemExtensionRequest) {}

    func request(_ request: OSSystemExtensionRequest, didFinishWithResult result: OSSystemExtensionRequest.Result) {
        continuation.resume()
    }

    func request(_ request: OSSystemExtensionRequest, didFailWithError error: Error) {
        continuation.resume(throwing: error)
    }
}
