import Dependencies
import Domain
import AVCameraPermission

extension DependencyValues {
    public var cameraPermission: any CameraPermission {
        get { self[CameraPermissionKey.self] }
        set { self[CameraPermissionKey.self] = newValue }
    }
}

private enum CameraPermissionKey: DependencyKey {
    static let liveValue: any CameraPermission = AVCameraPermission.live()
    static var testValue: any CameraPermission {
        unimplemented(
            #"@Dependency(\.cameraPermission)"#,
            placeholder: AlwaysGrantedCameraPermission() as any CameraPermission
        )
    }
}
