import Dependencies

/// カメラ認可を「取りに行く」port。
///
/// 役割：
///
/// - 起動時 / 初回利用前に `ensureGranted()` を呼ぶと、認可ステータスを問い合わせ、
///   未確定なら OS の認可ダイアログを駆動する。
/// - 既に拒否されている場合は「システム設定 > プライバシー > カメラ」へ
///   ユーザーを誘導するための alert を提示する（presenter は port 内側で
///   抽象化されているため UI フレームワークに依らない）。
///
/// 契約：
///
/// - 同じインスタンスに対して複数回 `ensureGranted()` を呼んでも安全。
///   2 回目以降は OS 側のステータスがそのまま返るため副作用は最小化される。
/// - `notDetermined` 中に並行で `ensureGranted()` が呼ばれた場合、OS の
///   `requestAccess` がプロセス毎に直列化されるので結果は一致する。
public protocol CameraPermission: Sendable {
    /// カメラ認可を確保しようと試みる。成功なら `.success`、それ以外は理由付きの `.failure`。
    func ensureGranted() async -> Result<Void, CameraPermissionError>
}

/// `CameraPermission.ensureGranted()` の失敗理由。
public enum CameraPermissionError: Error, Equatable, Sendable {
    /// ユーザーが拒否した、または以前から拒否されたまま。
    case denied
    /// ペアレンタルコントロール / MDM 等で利用そのものが制限されている。
    case restricted
}

public enum CameraPermissionKey: TestDependencyKey {
    public static let testValue: any CameraPermission = UnimplementedCameraPermission()
}

extension DependencyValues {
    public var cameraPermission: any CameraPermission {
        get { self[CameraPermissionKey.self] }
        set { self[CameraPermissionKey.self] = newValue }
    }
}

private struct UnimplementedCameraPermission: CameraPermission {
    func ensureGranted() async -> Result<Void, CameraPermissionError> {
        reportIssue(#"@Dependency(\.cameraPermission)"#)
        return .failure(.denied)
    }
}
