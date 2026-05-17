import Domain

/// `SystemExtensionInstaller` 内側 port。SystemExtensions framework の
/// `OSSystemExtensionRequest` を抽象化し、orchestrator がテスト可能になる。
///
/// 契約：
///
/// - `activate()` は activation request を OS に投げ、その遷移を
///   AsyncStream で push する。stream は最終状態 (`installed` /
///   `notInstalled`) に到達したら finish する。
/// - `deactivate()` は deactivation request を投げ、完了するまで suspend。
///   失敗時は throw。
public protocol SystemExtensionActivator: Sendable {
    func activate() async -> AsyncStream<CameraExtensionInstallStatus>
    func deactivate() async throws
}
