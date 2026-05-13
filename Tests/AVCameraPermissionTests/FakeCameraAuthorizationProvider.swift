@testable import AVCameraPermission

/// テスト用 `CameraAuthorizationProvider` 実装。
///
/// 初期 `status` を外部から差し替えて分岐を切り替える。
/// `requestAccess()` は事前指定した `grantOnRequest` の Bool を返すだけ ―
/// orchestrator 側は requestAccess の Bool 結果だけで成否を決めている
/// （`status` の再評価には依存しない）ので、fake にも status 遷移は不要。
actor FakeCameraAuthorizationProvider: CameraAuthorizationProvider {
    let status: CameraAuthorizationStatus
    private let grantOnRequest: Bool
    private(set) var requestAccessCallCount: Int = 0

    init(
        status: CameraAuthorizationStatus,
        grantOnRequest: Bool = false
    ) {
        self.status = status
        self.grantOnRequest = grantOnRequest
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        return grantOnRequest
    }
}
