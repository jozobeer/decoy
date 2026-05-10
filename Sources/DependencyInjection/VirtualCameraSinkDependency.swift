import Dependencies
import Domain
import InMemoryVirtualCameraSink

extension DependencyValues {
    public var virtualCameraSink: any VirtualCameraSink {
        get { self[VirtualCameraSinkKey.self] }
        set { self[VirtualCameraSinkKey.self] = newValue }
    }
}

private enum VirtualCameraSinkKey: DependencyKey {
    static let liveValue: any VirtualCameraSink = InMemoryVirtualCameraSink()
    static var testValue: any VirtualCameraSink { InMemoryVirtualCameraSink() }
}
