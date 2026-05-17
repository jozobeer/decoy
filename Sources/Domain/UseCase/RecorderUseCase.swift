import Dependencies
import Foundation

public enum RecorderEvent: Sendable {
    case saved(Clip)
    case saveFailed(any Error & Sendable)
}

/// AsyncSequence facade over `AsyncStream<RecorderEvent>`. Iterating
/// directly with `for await event in events { ... }` is equivalent to
/// iterating the underlying stream.
///
/// Lifecycle: this is a reference type so the actor-side subscriber
/// slot is released deterministically when every iterator AND every
/// external strong reference is dropped (Combine `AnyCancellable`
/// pattern). Cleanup converges from three paths, whichever fires first
/// wins and the others become idempotent no-ops:
///
/// 1. `RecorderEvents.deinit` — drop-driven cleanup when both the
///    handle and every iterator are released. Covers the "subscribed
///    but task cancelled before `for await` entered" race.
/// 2. The underlying `AsyncStream.onTermination` — cancellation-driven
///    cleanup for an iterating Task that gets cancelled.
/// 3. The actor's `broadcast` loop — lazy `.terminated` cleanup as a
///    final backstop.
public final class RecorderEvents: AsyncSequence, Sendable {
    public typealias Element = RecorderEvent

    private let stream: AsyncStream<RecorderEvent>
    private let cleanup: @Sendable () -> Void

    public init(stream: AsyncStream<RecorderEvent>, cleanup: @escaping @Sendable () -> Void) {
        self.stream = stream
        self.cleanup = cleanup
    }

    deinit { cleanup() }

    public func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(parent: self, inner: stream.makeAsyncIterator())
    }

    public struct AsyncIterator: AsyncIteratorProtocol {
        /// Strong ref keeps the parent `RecorderEvents` alive for the
        /// duration of iteration — without it, dropping the handle
        /// mid-iteration would fire cleanup while events are still
        /// being delivered.
        let parent: RecorderEvents
        var inner: AsyncStream<RecorderEvent>.AsyncIterator

        public mutating func next() async -> RecorderEvent? {
            await inner.next()
        }
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
        return RecorderEvents(stream: AsyncStream { $0.finish() }, cleanup: {})
    }

    func shutdown() async {
        reportIssue("RecorderUseCase.shutdown() called without a registered live or test value")
    }
}
