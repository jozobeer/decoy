import Domain

/// DI の `testValue` および unit test 用の `CameraPermission` スタブ。
///
/// 常に `.success(())` を返すだけ ― テストの SUT が「permission 取得済み」
/// 状態で動くようにするための placeholder。
///
/// 本物の実装は `AVCameraPermission` actor。production code から直接
/// 呼ぶことは想定していない（DI 経由でテスト時にだけ差し替える）。
public struct AlwaysGrantedCameraPermission: Sendable {
    public init() {}
}

extension AlwaysGrantedCameraPermission: CameraPermission {
    public func ensureGranted() async -> Result<Void, CameraPermissionError> {
        .success(())
    }
}
