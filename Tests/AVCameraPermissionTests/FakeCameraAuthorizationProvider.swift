import Foundation
@testable import AVCameraPermission

/// テスト用 `CameraAuthorizationProvider` 実装。
///
/// `status` は外部から差し替え、`requestAccess()` 後に
/// `postRequestStatus` で次回 `status` を変えられるようにしている
/// （実機の挙動：notDetermined → requestAccess → authorized/denied）。
actor FakeCameraAuthorizationProvider: CameraAuthorizationProvider {
    private var currentStatus: CameraAuthorizationStatus
    private let postRequestStatus: CameraAuthorizationStatus?
    private let grantOnRequest: Bool
    private(set) var requestAccessCallCount: Int = 0

    init(
        status: CameraAuthorizationStatus,
        grantOnRequest: Bool = false,
        postRequestStatus: CameraAuthorizationStatus? = nil
    ) {
        self.currentStatus = status
        self.grantOnRequest = grantOnRequest
        self.postRequestStatus = postRequestStatus
    }

    var status: CameraAuthorizationStatus {
        currentStatus
    }

    func requestAccess() async -> Bool {
        requestAccessCallCount += 1
        if let next = postRequestStatus {
            currentStatus = next
        }
        return grantOnRequest
    }
}
