import AVCameraPermission
import Dependencies
import Domain

extension CameraPermissionKey: DependencyKey {
    public static let liveValue: any CameraPermission = AVCameraPermission.live()
}
