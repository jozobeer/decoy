import Dependencies
import Foundation

public enum RecorderEvent: Sendable {
    case saved(Clip)
    case saveFailed(any Error & Sendable)
}

/// Passive value facade exposing the recorder's event stream plus an
/// explicit `cancel` closure for releasing the actor-side subscriber
/// slot. The wrapper itself carries no behavior — Domain only stores
/// the stream and the cleanup callback provided by the implementation
/// target, so coverage-ignored Domain remains a contract layer.
///
/// Cleanup contract: callers must invoke `cancel()` when done (use
/// `defer { Task { await events.cancel() } }` around `for await`), so
/// that subscriber slot release does not depend on iteration ever
/// starting. The implementation target's `cancel` closure is
/// idempotent and may be called from any cleanup path.
public struct RecorderEvents: Sendable, AsyncSequence {
    public typealias Element = RecorderEvent

    public let stream: AsyncStream<RecorderEvent>
    public let cancel: @Sendable () async -> Void

    public init(stream: AsyncStream<RecorderEvent>, cancel: @escaping @Sendable () async -> Void) {
        self.stream = stream
        self.cancel = cancel
    }

    public func makeAsyncIterator() -> AsyncStream<RecorderEvent>.AsyncIterator {
        stream.makeAsyncIterator()
    }
}

public protocol RecorderUseCase: Sendable {
    var state: RecordingState { get async }
    func handle(_ command: AppCommand) async
    func subscribeEvents() async -> RecorderEvents
    func shutdown() async
}

public enum RecorderUseCaseKey: TestDependencyKey {
    public static let testValue: any RecorderUseCase = UnimplementedRecorderUseCase()
}

extension DependencyValues {
    public var recorder: any RecorderUseCase {
        get { self[RecorderUseCaseKey.self] }
        set { self[RecorderUseCaseKey.self] = newValue }
    }
}

private actor UnimplementedRecorderUseCase: RecorderUseCase {
    var state: RecordingState {
        reportIssue("RecorderUseCase.state was accessed without a registered live or test value")
        return .idle
    }

    func handle(_ command: AppCommand) async {
        reportIssue("RecorderUseCase.handle(\(command)) called without a registered live or test value")
    }

    func subscribeEvents() async -> RecorderEvents {
        reportIssue("RecorderUseCase.subscribeEvents() called without a registered live or test value")
        return RecorderEvents(stream: AsyncStream { $0.finish() }, cancel: {})
    }

    func shutdown() async {
        reportIssue("RecorderUseCase.shutdown() called without a registered live or test value")
    }
}
