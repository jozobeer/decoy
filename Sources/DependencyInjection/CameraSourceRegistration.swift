import AVCameraSource
import Dependencies
import Domain
import InMemoryCameraSource

extension CameraSourceKey: DependencyKey {
    /// Live wiring: try the system camera; fall back to an empty
    /// in-memory source when the device is missing or permission is
    /// denied so the app boots without crashing. The actual UI layer
    /// is responsible for surfacing permission state to the user.
    public static let liveValue: any CameraSource = (try? AVCameraSource.live()) ?? InMemoryCameraSource()
}
