import Domain

public actor InMemoryVirtualCameraSink: VirtualCameraSink {
    public private(set) var frames: [Frame] = []

    public init() {}

    public func send(_ frame: Frame) async throws {
        frames.append(frame)
    }
}
