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

    /// Returns a fresh broadcast stream. Cleanup happens via two paths in
    /// this implementation:
    /// 1. `onTermination` fires when the consumer's task is cancelled
    ///    (the most common path: a test or view-model that wraps
    ///    iteration in `Task { ... }` cancels on teardown).
    /// 2. `broadcast` removes any subscriber whose `yield(_:)` returns
    ///    `.terminated`, providing a lazy cleanup at the next event.
    ///
    /// **Known gap**: if a caller obtains the stream and either abandons
    /// it without iterating, or breaks the `for-await` loop normally (no
    /// cancellation), neither path fires until the next broadcast catches
    /// `.terminated`. Long-running sessions with many such streams will
    /// accumulate stale entries. Tracked separately for a
    /// Subscription-token redesign in #17.
    public func subscribeEvents() -> AsyncStream<Event> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: Event.self,
            bufferingPolicy: .bufferingNewest(Self.subscriberBufferLimit)
        )
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id: id) }
        }
        return stream
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

    private func removeSubscriber(id: UUID) {
        subscribers.removeValue(forKey: id)
    }
}
