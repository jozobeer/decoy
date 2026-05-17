import Dependencies
import Foundation

public enum RecorderEvent: Sendable {
    case saved(Clip)
    case saveFailed(any Error & Sendable)
}

/// AsyncSequence facade over `AsyncStream<RecorderEvent>`. Iterating
/// directly with `for await event in events { ... }` is equivalent to
/// iterating the underlying stream; cleanup of the actor-side subscriber
/// slot is driven by the stream's `onTermination` callback when the
/// iterator drops or is cancelled.
public struct RecorderEvents: Sendable, AsyncSequence {
    public typealias Element = RecorderEvent

    private let stream: AsyncStream<RecorderEvent>

    public init(_ stream: AsyncStream<RecorderEvent>) {
        self.stream = stream
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
        return RecorderEvents(AsyncStream { $0.finish() })
    }

    func shutdown() async {
        reportIssue("RecorderUseCase.shutdown() called without a registered live or test value")
    }
}
