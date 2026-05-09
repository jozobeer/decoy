public protocol CameraSource: Sendable {
    func frames() async -> AsyncStream<Frame>
}
