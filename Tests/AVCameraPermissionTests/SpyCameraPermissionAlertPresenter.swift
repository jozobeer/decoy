@testable import AVCameraPermission

/// テスト用 `CameraPermissionAlertPresenter` 実装。
/// どちらの alert が何回呼ばれたかだけ記録する spy。
actor SpyCameraPermissionAlertPresenter: CameraPermissionAlertPresenter {
    private(set) var deniedAlertCount: Int = 0
    private(set) var restrictedAlertCount: Int = 0

    func presentDeniedAlert() async {
        deniedAlertCount += 1
    }

    func presentRestrictedAlert() async {
        restrictedAlertCount += 1
    }
}
