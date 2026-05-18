import Dependencies
import Foundation

public enum BroadcasterEvent: Sendable {
    case sendFailed(any Error & Sendable)
    case storeReadFailed(any Error & Sendable)
}

/// Passive value facade exposing the broadcaster's event stream plus an
/// explicit `cancel` closure for releasing the actor-side subscriber
/// slot. Mirrors `RecorderEvents` — Domain only stores the stream and
/// the cleanup callback provided by the implementation target, so
/// coverage-ignored Domain remains a contract layer.
///
/// Cleanup contract: callers must invoke `cancel()` when done (use
/// `defer { Task { await events.cancel() } }` around `for await`), so
/// that subscriber slot release does not depend on iteration ever
/// starting. The implementation target's `cancel` closure is
/// idempotent and may be called from any cleanup path.
public struct BroadcasterEvents: Sendable, AsyncSequence {
    public typealias Element = BroadcasterEvent

    public let stream: AsyncStream<BroadcasterEvent>
    public let cancel: @Sendable () async -> Void

    public init(stream: AsyncStream<BroadcasterEvent>, cancel: @escaping @Sendable () async -> Void) {
        self.stream = stream
        self.cancel = cancel
    }

    public func makeAsyncIterator() -> AsyncStream<BroadcasterEvent>.AsyncIterator {
        stream.makeAsyncIterator()
    }
}

public protocol BroadcasterUseCase: Sendable {
    var state: OutputMode { get async }
    func handle(_ command: AppCommand) async
    func subscribeEvents() async -> BroadcasterEvents
    func shutdown() async
}

public enum BroadcasterUseCaseKey: TestDependencyKey {
    public static let testValue: any BroadcasterUseCase = UnimplementedBroadcasterUseCase()
}

extension DependencyValues {
    public var broadcaster: any BroadcasterUseCase {
        get { self[BroadcasterUseCaseKey.self] }
        set { self[BroadcasterUseCaseKey.self] = newValue }
    }
}

private actor UnimplementedBroadcasterUseCase: BroadcasterUseCase {
    var state: OutputMode {
        reportIssue("BroadcasterUseCase.state was accessed without a registered live or test value")
        return .live
    }

    func handle(_ command: AppCommand) async {
        reportIssue("BroadcasterUseCase.handle(\(command)) called without a registered live or test value")
    }

    func subscribeEvents() async -> BroadcasterEvents {
        reportIssue("BroadcasterUseCase.subscribeEvents() called without a registered live or test value")
        return BroadcasterEvents(stream: AsyncStream { $0.finish() }, cancel: {})
    }

    func shutdown() async {
        reportIssue("BroadcasterUseCase.shutdown() called without a registered live or test value")
    }
}
