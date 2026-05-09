import Domain

public actor InMemoryCameraSource: CameraSource {
    public private(set) var subscribeCount = 0
    private let preset: [Frame]

    public init(emitting frames: [Frame] = []) {
        self.preset = frames
    }

    public func frames() async -> AsyncStream<Frame> {
        // tdd-impl phase: not yet implemented
        AsyncStream { $0.finish() }
    }
}
