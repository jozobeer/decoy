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
    /// underlying subscriber slot. Cleanup happens via three converging
    /// paths — whichever fires first removes the bookkeeping entry, and
    /// the others become idempotent no-ops:
    /// 1. `Subscription.deinit` — fires deterministically when the
    ///    caller drops the token (out-of-scope, never iterated,
    ///    `for-await break`, abandoned in storage, etc.). Combine's
    ///    `AnyCancellable` pattern.
    /// 2. `onTermination` — fires when the consumer's iteration Task is
    ///    cancelled (the legacy path; still valuable for callers that
    ///    wrap iteration in a cancellable Task and rely on cancellation
    ///    propagation).
    /// 3. `broadcast` — removes any subscriber whose `yield(_:)` returns
    ///    `.terminated` on the next event (final backstop).
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
        return Subscription(events: stream) { [weak self] in
            Task { await self?.removeSubscriber(id: id) }
        }
    }
}

public extension Recorder {
    /// Strong-ref token returned by `subscribeEvents()`. Drop the token
    /// (out-of-scope, deinit) to deterministically remove the subscriber
    /// slot — closes the "never iterated" / "for-await break" gap that
    /// the bare `AsyncStream` return type left open.
    final class Subscription: Sendable {
        public let events: AsyncStream<Event>
        private let cleanup: @Sendable () -> Void

        init(events: AsyncStream<Event>, cleanup: @escaping @Sendable () -> Void) {
            self.events = events
            self.cleanup = cleanup
        }

        deinit { cleanup() }
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
    /// stream. Without the `finish()` call, a consumer that extracted
    /// `subscription.events` into a long-lived `Task` (separate from the
    /// token's lifetime) would hang on the next `await` after we drop
    /// the dict entry, because their `AsyncStream` value still holds
    /// the buffer alive and never sees termination.
    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)?.finish()
    }

    /// Test-only hook for verifying cleanup. Reflects the live size of
    /// the subscribers dict.
    internal var subscriberCount: Int { subscribers.count }
}
