import Foundation
import OSLog
import Dependencies
import DependencyInjection
import Domain

public actor Broadcaster {
    public enum Event: Sendable {
        case sendFailed(any Error & Sendable)
        case storeReadFailed(any Error & Sendable)
    }

    private nonisolated let cameraSource: any CameraSource
    private nonisolated let virtualCameraSink: any VirtualCameraSink
    private nonisolated let clipStore: any ClipStore
    private nonisolated let clock: any Clock<Duration>

    public private(set) var state: OutputMode
    private var routing: Task<Void, Never>?
    private var subscribers: [UUID: AsyncStream<Event>.Continuation] = [:]
    /// Sticky flag: once `shutdown()` runs, any subsequent
    /// `startRouting()` is a no-op. Defends the deferred init-task hop
    /// against a caller that does `Broadcaster() → await shutdown()`
    /// before the actor has processed the init's `startRouting()` hop.
    private var terminated = false

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "Broadcaster")
    private static let subscriberBufferLimit = 64

    public init(state: OutputMode = .live) {
        @Dependency(\.cameraSource) var cameraSource
        @Dependency(\.virtualCameraSink) var virtualCameraSink
        @Dependency(\.clipStore) var clipStore
        @Dependency(\.continuousClock) var clock
        self.cameraSource = cameraSource
        self.virtualCameraSink = virtualCameraSink
        self.clipStore = clipStore
        self.clock = clock
        self.state = state
        // Initial routing is started via a hop back into the actor so
        // we can build an `emit` closure that captures fully-initialized
        // self. Doing it in init's body would force the closure to
        // capture self before stored properties are set, which Swift's
        // actor isolation rules reject.
        Task { [weak self] in
            await self?.startRouting()
        }
    }

    public func handle(_ command: AppCommand) async {
        if terminated { return }
        switch command {
        case .startDecoy(let mode):
            let target = OutputMode.playback(mode)
            // Same-mode + routing still alive is a true no-op. But if
            // routing has wound down (.once finished naturally, store
            // was empty at init, etc.) we must restart so callers can
            // replay without bouncing through .returnToLive.
            if target == state, routing != nil { return }
            state = target
            await stopRouting()
            startRouting()
        case .returnToLive:
            // Symmetric to startDecoy: only no-op when live routing is
            // actually running. A dead live task (source closed
            // naturally) should be restartable.
            if state == .live, routing != nil { return }
            state = .live
            await stopRouting()
            startRouting()
        case .startRecording, .stopRecording:
            break
        }
    }

    public func shutdown() async {
        terminated = true
        await stopRouting()
    }

    /// Returns a fresh broadcast stream. Cleanup mirrors `Recorder` —
    /// `onTermination` removes the subscriber on consumer cancel, and
    /// `broadcast` does lazy cleanup of `.terminated` continuations on
    /// the next event. Known gap (same as Recorder): consumers that
    /// abandon the stream without cancellation leave stale entries
    /// until the next broadcast catches `.terminated`. Tracked in #17
    /// for a Subscription-token redesign that would cover both actors.
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

extension Broadcaster {
    /// Floor for inter-frame sleep duration. Single-frame `.pingPong`
    /// clips, or clips with identical adjacent pts, would otherwise
    /// hot-spin the routing task. 1ms is below human perception and
    /// short enough to drain instantly under `ImmediateClock` in tests.
    private static let minimumFrameGap: Double = 0.001

    private func startRouting() {
        guard !terminated, routing == nil else { return }
        let emit: @Sendable (Event) async -> Void = { [weak self] event in
            await self?.broadcast(event)
        }
        let task = Self.makeRoutingTask(
            state: state,
            source: cameraSource,
            store: clipStore,
            sink: virtualCameraSink,
            clock: clock,
            emit: emit
        )
        routing = task
        Task { [weak self] in
            _ = await task.value
            await self?.routingDidComplete(task)
        }
    }

    /// Cancel the active routing task and wait for it to fully wind down.
    /// `routing` stays non-nil during the await so a concurrent
    /// `startRouting()` (via actor re-entrancy) can't spawn a second
    /// task while the old one is still draining. Identity-check at the
    /// end so a stop+restart sequence doesn't clobber the new task.
    private func stopRouting() async {
        guard let task = routing else { return }
        task.cancel()
        await task.value
        if routing == task {
            routing = nil
        }
    }

    /// Called when a routing task finishes — naturally (source closed,
    /// playback completed, store empty) or via cancellation. Only clears
    /// `routing` when the completing task is the one we currently track,
    /// so a stop+restart sequence doesn't accidentally drop the new task.
    private func routingDidComplete(_ task: Task<Void, Never>) {
        if routing == task {
            routing = nil
        }
    }

    /// Fan out an event to all live subscribers. `.terminated`
    /// continuations are dropped from the map lazily on the next emit.
    private func broadcast(_ event: Event) {
        let snapshot = subscribers
        let terminated = snapshot.compactMap { id, continuation -> UUID? in
            switch continuation.yield(event) {
            case .enqueued: return nil
            case .dropped:
                Self.logger.warning("Broadcaster event dropped for subscriber \(id.uuidString, privacy: .public) (buffer full)")
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

    private static func makeRoutingTask(
        state: OutputMode,
        source: any CameraSource,
        store: any ClipStore,
        sink: any VirtualCameraSink,
        clock: any Clock<Duration>,
        emit: @escaping @Sendable (Event) async -> Void
    ) -> Task<Void, Never> {
        switch state {
        case .live:
            return makeLiveRoutingTask(source: source, sink: sink, emit: emit)
        case .playback(let mode):
            return makePlaybackRoutingTask(mode: mode, store: store, sink: sink, clock: clock, emit: emit)
        }
    }

    private static func makeLiveRoutingTask(
        source: any CameraSource,
        sink: any VirtualCameraSink,
        emit: @escaping @Sendable (Event) async -> Void
    ) -> Task<Void, Never> {
        Task {
            let stream = await source.frames()
            for await frame in stream {
                if Task.isCancelled { break }
                do {
                    try await sink.send(frame)
                } catch is CancellationError {
                    break
                } catch {
                    if Task.isCancelled { break }
                    await emit(.sendFailed(error))
                }
            }
        }
    }

    private static func makePlaybackRoutingTask(
        mode: PlaybackMode,
        store: any ClipStore,
        sink: any VirtualCameraSink,
        clock: any Clock<Duration>,
        emit: @escaping @Sendable (Event) async -> Void
    ) -> Task<Void, Never> {
        Task {
            let clip: Clip?
            do {
                clip = try await latestClip(in: store)
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                await emit(.storeReadFailed(error))
                return
            }
            guard let clip, !clip.frames.isEmpty else { return }
            await emitFrames(clip.frames, mode: mode, sink: sink, clock: clock, emit: emit)
        }
    }

    /// Pick the most recently recorded clip from the store. Returns nil
    /// when the store is empty so callers can skip routing cleanly.
    private static func latestClip(in store: any ClipStore) async throws -> Clip? {
        try await store.all().max(by: { $0.recordedAt < $1.recordedAt })
    }

    private static func emitFrames(
        _ frames: [Frame],
        mode: PlaybackMode,
        sink: any VirtualCameraSink,
        clock: any Clock<Duration>,
        emit: @escaping @Sendable (Event) async -> Void
    ) async {
        var index = 0
        var direction = 1

        while !Task.isCancelled {
            do {
                try await sink.send(frames[index])
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                await emit(.sendFailed(error))
            }

            guard let next = nextIndex(
                current: index,
                direction: &direction,
                frameCount: frames.count,
                mode: mode
            ) else { return }

            let gap = gapBetween(current: index, next: next, frames: frames, mode: mode)
            try? await clock.sleep(for: .seconds(gap))
            if Task.isCancelled { return }
            index = next
        }
    }

    /// Inter-frame sleep duration. Normally the absolute pts difference,
    /// floored at `minimumFrameGap`. `.loop` wrap (last → first) snaps
    /// to `minimumFrameGap` so the cycle boundary doesn't stall for the
    /// full clip duration — otherwise the loop period would be roughly
    /// `2 * duration` instead of `duration`.
    static func gapBetween(
        current: Int,
        next: Int,
        frames: [Frame],
        mode: PlaybackMode
    ) -> Double {
        if case .loop = mode, next < current { return minimumFrameGap }
        let delta = abs(frames[next].presentationTime - frames[current].presentationTime)
        return max(delta, minimumFrameGap)
    }

    /// Compute the next frame index for the active playback mode.
    /// `direction` is `inout` because .pingPong flips between forward
    /// and reverse at endpoints. Returns nil only for .once at the last
    /// frame — the signal to terminate the routing task naturally.
    /// Pattern for N≥2 .pingPong (no endpoint duplication):
    /// A B C B A B C B A ... (period = 2N-2).
    private static func nextIndex(
        current: Int,
        direction: inout Int,
        frameCount: Int,
        mode: PlaybackMode
    ) -> Int? {
        switch mode {
        case .once:
            return current == frameCount - 1 ? nil : current + 1
        case .loop:
            return (current + 1) % frameCount
        case .pingPong:
            return pingPongNext(current: current, direction: &direction, frameCount: frameCount)
        }
    }

    /// .pingPong step: walk one slot in the current direction; if that
    /// would step off either end, flip `direction` and bounce back to
    /// the mirrored neighbour. Single-frame clips have no direction to
    /// flip — return `current` so emit keeps yielding the same frame.
    private static func pingPongNext(
        current: Int,
        direction: inout Int,
        frameCount: Int
    ) -> Int {
        guard frameCount > 1 else { return current }
        let next = current + direction
        guard next < 0 || next >= frameCount else { return next }
        direction *= -1
        return current + direction
    }
}

