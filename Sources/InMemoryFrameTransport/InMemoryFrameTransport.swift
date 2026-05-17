import Domain
import Foundation

/// `FrameTransport` のテスト / プレビュー用 stub。
///
/// Mach port / IOSurface などの REALWORLD には触れず、in-process で
/// frame を受け取って配列に積む。spec test は本 stub を「extension 側
/// receiver の理想形」と見立てて round-trip を検証する。
///
/// `testValue` プレースホルダとして DI に注入される。実テストでは
/// `withDependencies` で具体的な fake / mock を差し替える。
public actor InMemoryFrameTransport {
    public private(set) var sentFrames: [Frame] = []
    public private(set) var isConnected: Bool = false
    /// `connect()` が一度でも成功したかを保持する。`disconnect()` 後の
    /// `send(_:)` を `.disconnectedDuringSend` として区別するために使う。
    public private(set) var wasConnected: Bool = false

    private var continuations: [UUID: AsyncStream<FrameTransportEvent>.Continuation] = [:]
    private var currentState: FrameTransportEvent = .disconnected

    public init() {}
}

extension InMemoryFrameTransport: FrameTransport {
    public var events: AsyncStream<FrameTransportEvent> {
        AsyncStream { continuation in
            let id = UUID()
            let initial = currentState
            continuations[id] = continuation
            continuation.yield(initial)
            continuation.onTermination = { [weak self] _ in
                Task { [weak self] in await self?.removeContinuation(id: id) }
            }
        }
    }

    public func connect() async throws {
        guard !isConnected else { return }
        isConnected = true
        wasConnected = true
        emit(.connected)
    }

    public func disconnect() async {
        guard isConnected else { return }
        isConnected = false
        emit(.disconnected)
    }

    public func send(_ frame: Frame) async throws {
        guard isConnected else {
            throw wasConnected ? FrameTransportError.disconnectedDuringSend : FrameTransportError.notConnected
        }
        sentFrames.append(frame)
    }
}

extension InMemoryFrameTransport {
    private func emit(_ event: FrameTransportEvent) {
        currentState = event
        continuations.values.forEach { $0.yield(event) }
    }

    private func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
