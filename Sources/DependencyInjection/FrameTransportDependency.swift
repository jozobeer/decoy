import Dependencies
import Domain
import InMemoryFrameTransport

extension DependencyValues {
    public var frameTransport: any FrameTransport {
        get { self[FrameTransportKey.self] }
        set { self[FrameTransportKey.self] = newValue }
    }
}

private enum FrameTransportKey: DependencyKey {
    static let liveValue: any FrameTransport = InMemoryFrameTransport()
    static var testValue: any FrameTransport {
        unimplemented(
            #"@Dependency(\.frameTransport)"#,
            placeholder: InMemoryFrameTransport() as any FrameTransport
        )
    }
}
