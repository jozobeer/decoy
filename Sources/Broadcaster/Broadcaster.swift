import Dependencies
import DependencyInjection
import Domain

public actor Broadcaster {
    private nonisolated let cameraSource: any CameraSource
    private nonisolated let virtualCameraSink: any VirtualCameraSink
    private nonisolated let clipStore: any ClipStore
    private nonisolated let clock: any Clock<Duration>

    public private(set) var state: OutputMode
    private var routing: Task<Void, Never>?

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
        let task = Self.makeRoutingTask(
            state: state,
            source: cameraSource,
            store: clipStore,
            sink: virtualCameraSink,
            clock: clock
        )
        self.routing = task
        Task { [weak self] in
            _ = await task.value
            await self?.routingDidComplete(task)
        }
    }

    public func handle(_ command: AppCommand) async {
        switch command {
        case .startDecoy(let mode):
            let target = OutputMode.playback(mode)
            guard target != state else { return }
            state = target
            await stopRouting()
            startRouting()
        case .returnToLive:
            guard state != .live else { return }
            state = .live
            await stopRouting()
            startRouting()
        case .startRecording, .stopRecording:
            break
        }
    }

    public func shutdown() async {
        await stopRouting()
    }
}

extension Broadcaster {
    /// Floor for inter-frame sleep duration. Single-frame `.pingPong`
    /// clips, or clips with identical adjacent pts, would otherwise
    /// hot-spin the routing task. 1ms is below human perception and
    /// short enough to drain instantly under `ImmediateClock` in tests.
    private static let minimumFrameGap: Double = 0.001

    private func startRouting() {
        guard routing == nil else { return }
        let task = Self.makeRoutingTask(
            state: state,
            source: cameraSource,
            store: clipStore,
            sink: virtualCameraSink,
            clock: clock
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

    private static func makeRoutingTask(
        state: OutputMode,
        source: any CameraSource,
        store: any ClipStore,
        sink: any VirtualCameraSink,
        clock: any Clock<Duration>
    ) -> Task<Void, Never> {
        switch state {
        case .live:
            return makeLiveRoutingTask(source: source, sink: sink)
        case .playback(let mode):
            return makePlaybackRoutingTask(mode: mode, store: store, sink: sink, clock: clock)
        }
    }

    private static func makeLiveRoutingTask(
        source: any CameraSource,
        sink: any VirtualCameraSink
    ) -> Task<Void, Never> {
        Task {
            let stream = await source.frames()
            for await frame in stream {
                if Task.isCancelled { break }
                try? await sink.send(frame)
            }
        }
    }

    private static func makePlaybackRoutingTask(
        mode: PlaybackMode,
        store: any ClipStore,
        sink: any VirtualCameraSink,
        clock: any Clock<Duration>
    ) -> Task<Void, Never> {
        Task {
            guard
                let clip = try? await latestClip(in: store),
                !clip.frames.isEmpty
            else { return }
            await emit(frames: clip.frames, mode: mode, sink: sink, clock: clock)
        }
    }

    /// Pick the most recently recorded clip from the store. Returns nil
    /// when the store is empty so callers can skip routing cleanly.
    private static func latestClip(in store: any ClipStore) async throws -> Clip? {
        try await store.all().max(by: { $0.recordedAt < $1.recordedAt })
    }

    private static func emit(
        frames: [Frame],
        mode: PlaybackMode,
        sink: any VirtualCameraSink,
        clock: any Clock<Duration>
    ) async {
        var index = 0
        var direction = 1

        while !Task.isCancelled {
            try? await sink.send(frames[index])

            guard let next = nextIndex(
                current: index,
                direction: &direction,
                frameCount: frames.count,
                mode: mode
            ) else { return }

            let gap = max(
                abs(frames[next].presentationTime - frames[index].presentationTime),
                minimumFrameGap
            )
            try? await clock.sleep(for: .seconds(gap))
            if Task.isCancelled { return }
            index = next
        }
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
