import Domain

public actor InMemoryCameraSource: CameraSource {
    public private(set) var subscribeCount = 0
    private let preset: [Frame]

    public init(emitting frames: [Frame] = []) {
        self.preset = frames
    }

    public func frames() async -> AsyncStream<Frame> {
        subscribeCount += 1
        let snapshot = preset
        return AsyncStream { continuation in
            snapshot.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }
}
