import CMIOVirtualCameraSink
import Dependencies
import Domain
import InMemoryFrameTransport
import InMemoryVirtualCameraSink

extension DependencyValues {
    public var virtualCameraSink: any VirtualCameraSink {
        get { self[VirtualCameraSinkKey.self] }
        set { self[VirtualCameraSinkKey.self] = newValue }
    }
}

private enum VirtualCameraSinkKey: DependencyKey {
    // CMIOVirtualCameraSink を本実装として使う。transport は #43 stage 2 で
    // MachPortFrameTransport に差し替わる ― 現状は InMemoryFrameTransport を
    // 注入しているので frame は in-process バッファに溜まるだけだが、
    // Broadcaster → CMIOVirtualCameraSink → FrameTransport の配線は本物。
    static let liveValue: any VirtualCameraSink = CMIOVirtualCameraSink(transport: InMemoryFrameTransport())
    static var testValue: any VirtualCameraSink {
        unimplemented(
            #"@Dependency(\.virtualCameraSink)"#,
            placeholder: InMemoryVirtualCameraSink() as any VirtualCameraSink
        )
    }
}
