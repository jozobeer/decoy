import Dependencies
import Domain
import InMemoryFrameTransport

extension FrameTransportKey: DependencyKey {
    public static let liveValue: any FrameTransport = InMemoryFrameTransport()
}
