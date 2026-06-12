import CMIOVirtualCameraSink
import Dependencies
import Domain

extension VirtualCameraSinkKey: DependencyKey {
    public static var liveValue: any VirtualCameraSink {
        @Dependency(\.frameTransport) var transport
        @Dependency(\.cameraExtensionInstaller) var installer
        return CMIOVirtualCameraSink(transport: transport, installer: installer)
    }
}
