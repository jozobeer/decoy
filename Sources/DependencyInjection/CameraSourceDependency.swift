import Dependencies
import Domain
import InMemoryCameraSource
import AVCameraSource

extension DependencyValues {
    public var cameraSource: any CameraSource {
        get { self[CameraSourceKey.self] }
        set { self[CameraSourceKey.self] = newValue }
    }
}

private enum CameraSourceKey: DependencyKey {
    /// Live wiring: try the system camera; fall back to an empty
    /// in-memory source when the device is missing or permission is
    /// denied so the app boots without crashing. The actual UI layer
    /// is responsible for surfacing permission state to the user.
    static let liveValue: any CameraSource = (try? AVCameraSource.live()) ?? InMemoryCameraSource()
    static var testValue: any CameraSource {
        unimplemented(
            #"@Dependency(\.cameraSource)"#,
            placeholder: InMemoryCameraSource() as any CameraSource
        )
    }
}
