import CMIOVirtualCameraSink
import Dependencies
import Domain

extension VirtualCameraSinkKey: DependencyKey {
    public static var liveValue: any VirtualCameraSink {
        @Dependency(\.frameTransport) var transport
        return CMIOVirtualCameraSink(transport: transport)
    }
}
