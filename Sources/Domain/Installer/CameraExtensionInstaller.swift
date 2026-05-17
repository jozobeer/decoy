import Dependencies

/// CMIO Camera Extension の install 状態を駆動する port。
///
/// 役割：
///
/// - `activate()` でホストアプリに同梱されている SystemExtension bundle
///   (`DecoyCameraExtension`) を OS に登録依頼する。
/// - 状態は `status` の AsyncStream で push される ―
///   `notInstalled` → `installing` → `needsApproval` (ユーザーが
///   System Settings で許可待ち) → `installed`。
/// - `deactivate()` で SystemExtension を uninstall。
///
/// 契約：
///
/// - `activate()` を複数回呼んでも、進行中の request が既にあれば
///   重複 install は走らない（OS 側でも `systemextensionsctl` が
///   in-flight request を弾く）。
/// - `status` stream は subscribe 時点の最新値を初回 emit してから
///   遷移を流す。subscriber が複数いても各々が同じ値列を受け取る。
public protocol CameraExtensionInstaller: Sendable {
    var status: AsyncStream<CameraExtensionInstallStatus> { get async }
    func activate() async
    func deactivate() async
}

/// CMIO Camera Extension の install 状態。`CameraExtensionInstaller.status`
/// が流す値。
public enum CameraExtensionInstallStatus: Sendable, Equatable {
    /// まだ activate 要求が出ていない / 過去に uninstall された状態。
    case notInstalled
    /// `activate()` 要求が出ており、OS の install 処理が進行中。
    case installing
    /// install は完了したがユーザーの System Settings 上での許可待ち。
    case needsApproval
    /// install 完了 ― 外部アプリ (Zoom 等) から「Decoy」が選べる。
    case installed
}

public enum CameraExtensionInstallerKey: TestDependencyKey {
    public static let testValue: any CameraExtensionInstaller = UnimplementedCameraExtensionInstaller()
}

extension DependencyValues {
    public var cameraExtensionInstaller: any CameraExtensionInstaller {
        get { self[CameraExtensionInstallerKey.self] }
        set { self[CameraExtensionInstallerKey.self] = newValue }
    }
}

private struct UnimplementedCameraExtensionInstaller: CameraExtensionInstaller {
    var status: AsyncStream<CameraExtensionInstallStatus> {
        get async {
            reportIssue(#"@Dependency(\.cameraExtensionInstaller)"#)
            return AsyncStream { $0.finish() }
        }
    }
    func activate() async {
        reportIssue(#"@Dependency(\.cameraExtensionInstaller)"#)
    }
    func deactivate() async {
        reportIssue(#"@Dependency(\.cameraExtensionInstaller)"#)
    }
}
