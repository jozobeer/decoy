import Dependencies
import Domain
import MachPortFrameTransport

extension FrameTransportKey: DependencyKey {
    public static let liveValue: any FrameTransport = MachPortFrameTransport.live(
        serviceName: FrameTransportServiceName.mach
    )
}
