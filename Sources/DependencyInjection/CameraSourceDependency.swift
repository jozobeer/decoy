import Dependencies
import Domain
import InMemoryCameraSource

extension DependencyValues {
    public var cameraSource: any CameraSource {
        get { self[CameraSourceKey.self] }
        set { self[CameraSourceKey.self] = newValue }
    }
}

private enum CameraSourceKey: DependencyKey {
    static let liveValue: any CameraSource = InMemoryCameraSource()
    static var testValue: any CameraSource { InMemoryCameraSource() }
}
