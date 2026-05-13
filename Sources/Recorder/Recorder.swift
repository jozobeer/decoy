import Foundation
import OSLog
import Dependencies
import DependencyInjection
import Domain

public actor Recorder {
    public enum Event: Sendable {
        case saved(Clip)
        case saveFailed(any Error & Sendable)
    }

    @Dependency(\.cameraSource) private var cameraSource
    @Dependency(\.clipStore) private var clipStore
    @Dependency(\.date) private var date
    @Dependency(\.uuid) private var uuid

    public private(set) var state: RecordingState = .idle
    private var consumption: Task<Void, Never>?
    private var buffer: [Frame] = []
    private var recordedAt: Date?
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "Recorder")
    private static let subscriberBufferLimit = 64

    public init() {}

    public func handle(_ command: AppCommand) async {
        switch command {
        case .startRecording:
            await beginRecording()
        case .stopRecording:
            await endRecording()
        case .startDecoy, .returnToLive:
            break
        }
    }

    /// Returns a `Subscription` token whose lifetime owns the
    /// underlying subscriber slot. The token IS the `AsyncSequence` —
    /// `for await event in subscription { ... }` — and its iterator
    /// strongly retains the token, so iteration cannot outlive
    /// ownership. Cleanup converges from three paths, whichever fires
    /// first wins and the others become idempotent no-ops:
    /// 1. `Subscription.deinit` — deterministic drop-driven cleanup
    ///    when every iterator AND every external strong reference is
    ///    released (Combine `AnyCancellable` pattern).
    /// 2. `onTermination` — cancellation-driven cleanup for iteration
    ///    Tasks that cancel.
    /// 3. `broadcast` — lazy `.terminated` cleanup as a final backstop.
    public func subscribeEvents() -> Subscription {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Event.self,
            bufferingPolicy: .bufferingNewest(Self.subscriberBufferLimit)
        )
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id: id) }
        }
        return Subscription(stream: stream) { [weak self] in
            Task { await self?.removeSubscriber(id: id) }
        }
    }
}

public extension Recorder {
    /// Strong-ref token returned by `subscribeEvents()`. Iterate it
    /// directly with `for await event in subscription` — the iterator
    /// retains the token, so the consumer can't accidentally release
    /// ownership while iterating. Drop every reference (token + all
    /// active iterators) to deterministically remove the subscriber
    /// slot.
    final class Subscription: AsyncSequence, Sendable {
        public typealias Element = Event

        private let stream: AsyncStream<Event>
        private let cleanup: @Sendable () -> Void

        init(stream: AsyncStream<Event>, cleanup: @escaping @Sendable () -> Void) {
            self.stream = stream
            self.cleanup = cleanup
        }

        deinit { cleanup() }

        public func makeAsyncIterator() -> AsyncIterator {
            AsyncIterator(subscription: self, inner: stream.makeAsyncIterator())
        }

        public struct AsyncIterator: AsyncIteratorProtocol {
            /// Strong ref keeps the parent `Subscription` alive for the
            /// duration of iteration — closes the gap where extracting
            /// the stream from a temporary token would let ARC release
            /// the token before any event was delivered.
            let subscription: Subscription
            var inner: AsyncStream<Event>.AsyncIterator

            public mutating func next() async -> Event? {
                await inner.next()
            }
        }
    }
}

extension Recorder {
    private func beginRecording() async {
        guard state == .idle else { return }
        state = .recording
        recordedAt = date.now
        buffer = []
        let source = cameraSource
        consumption = Task { [weak self] in
            let stream = await source.frames()
            for await frame in stream {
                await self?.append(frame)
            }
            await self?.finishRecording()
        }
    }

    private func endRecording() async {
        guard state == .recording else { return }
        consumption?.cancel()
        await consumption?.value
    }

    private func append(_ frame: Frame) {
        buffer.append(frame)
    }

    private func finishRecording() async {
        defer {
            state = .idle
            consumption = nil
            buffer = []
            recordedAt = nil
        }
        guard let first = buffer.first, let last = buffer.last, let recordedAt = recordedAt else { return }
        let clip = Clip(
            id: uuid(),
            recordedAt: recordedAt,
            frames: buffer,
            duration: last.presentationTime - first.presentationTime
        )
        do {
            try await clipStore.save(clip)
            broadcast(.saved(clip))
        } catch {
            Self.logger.error("ClipStore.save failed: \(error.localizedDescription, privacy: .private)")
            broadcast(.saveFailed(error))
        }
    }

    private func broadcast(_ event: Event) {
        let snapshot = subscribers
        let terminated = snapshot.compactMap { id, continuation -> UUID? in
            switch continuation.yield(event) {
            case .enqueued: return nil
            case .dropped:
                Self.logger.warning("Recorder event dropped for subscriber \(id.uuidString, privacy: .public) (buffer full)")
                return nil
            case .terminated: return id
            @unknown default: return nil
            }
        }
        terminated.forEach { subscribers.removeValue(forKey: $0) }
    }

    /// Unregister the subscriber AND deterministically terminate its
    /// stream. The `finish()` ensures any active iterator exits cleanly
    /// when cleanup runs from a path other than the iterator itself
    /// (e.g., `onTermination` from a cancelled Task).
    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)?.finish()
    }

    /// Test-only hook for verifying cleanup. Reflects the live size of
    /// the subscribers dict.
    internal var subscriberCount: Int { subscribers.count }
}
