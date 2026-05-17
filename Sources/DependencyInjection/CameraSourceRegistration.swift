import AVCameraSource
import Dependencies
import Domain
import InMemoryCameraSource

extension CameraSourceKey: DependencyKey {
    public static let liveValue: any CameraSource = (try? AVCameraSource.live()) ?? InMemoryCameraSource()
}
