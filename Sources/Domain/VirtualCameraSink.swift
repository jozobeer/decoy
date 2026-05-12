public protocol VirtualCameraSink: Sendable {
    func send(_ frame: Frame) async throws
}
