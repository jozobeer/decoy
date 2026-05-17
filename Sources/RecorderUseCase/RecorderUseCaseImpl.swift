import Foundation
import OSLog
import Dependencies
import Domain

public actor RecorderUseCaseImpl {
    @Dependency(\.cameraSource) private var cameraSource
    @Dependency(\.clipStore) private var clipStore
    @Dependency(\.date) private var date
    @Dependency(\.uuid) private var uuid

    public private(set) var state: RecordingState = .idle
    private var consumption: Task<Void, Never>?
    private var buffer: [Frame] = []
    private var recordedAt: Date?
    private var subscribers: [UUID: AsyncStream<RecorderEvent>.Continuation] = [:]
    /// Sticky flag mirroring `Broadcaster.terminated`. Once `shutdown()`
    /// runs, any concurrent re-entry into `handle(.startRecording)` that
    /// resumes after the await is a no-op — actor reentrancy would
    /// otherwise let a new consumption Task spawn after `shutdown()`
    /// cancels the old one, escaping the terminal cleanup.
    private var terminated = false

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "Recorder")
    private static let subscriberBufferLimit = 64

    public init() {}
}

extension RecorderUseCaseImpl: RecorderUseCase {
    public func handle(_ command: AppCommand) async {
        if terminated { return }
        switch command {
        case .startRecording:
            await beginRecording()
        case .stopRecording:
            await endRecording()
        case .startDecoy, .returnToLive:
            break
        }
    }

    public func subscribeEvents() async -> RecorderEvents {
        let (stream, continuation) = AsyncStream.makeStream(
            of: RecorderEvent.self,
            bufferingPolicy: .bufferingNewest(Self.subscriberBufferLimit)
        )
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id: id) }
        }
        return RecorderEvents(
            stream: stream,
            cancel: { [weak self] in
                await self?.removeSubscriber(id: id)
            }
        )
    }

    public func shutdown() async {
        terminated = true
        consumption?.cancel()
        await consumption?.value
        subscribers.values.forEach { $0.finish() }
        subscribers.removeAll()
    }
}

extension RecorderUseCaseImpl {
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

    private func broadcast(_ event: RecorderEvent) {
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
        subscribers.removeValue(forKey: id)?.finish()
    }

    internal var subscriberCount: Int { subscribers.count }
}
