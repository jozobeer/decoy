import Domain

/// `CameraExtensionInstaller` のテスト / プレビュー用 stub。常に
/// `installed` 状態を返し、`activate()` / `deactivate()` は no-op。
///
/// `testValue` プレースホルダとして DI に注入される。実テストでは
/// `withDependencies` で具体的な fake / mock を差し替える。
public struct AlwaysInstalledSystemExtensionInstaller: Sendable {
    public init() {}
}

extension AlwaysInstalledSystemExtensionInstaller: CameraExtensionInstaller {
    public var status: AsyncStream<CameraExtensionInstallStatus> {
        AsyncStream { continuation in
            continuation.yield(.installed)
            continuation.finish()
        }
    }

    public func activate() async {}
    public func deactivate() async {}
}
