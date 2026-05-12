import Testing
import Foundation
import Clocks
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
import InMemoryVirtualCameraSink
@testable import Broadcaster

@Suite("BroadcasterIntegration", .timeLimit(.minutes(1)))
struct BroadcasterIntegrationTests {

    // MARK: - Fixtures

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Live Mode Routing

    @Test func defaultInit_routesLiveFramesToSink() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let frames = await collectFrames(from: sink, atLeast: 1)
            await broadcaster.shutdown()

            #expect(frames.count == 1)
            #expect(await broadcaster.state == .live)
        }
    }

    @Test func explicitLiveInit_routesFramesToSink() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .live)
            let frames = await collectFrames(from: sink, atLeast: 1)
            await broadcaster.shutdown()

            #expect(frames.count == 1)
        }
    }

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func playbackInit_doesNotRouteFrames(mode: PlaybackMode) async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0), Self.frame(0.1)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(mode))
            let frames = await collectFrames(from: sink, atLeast: 0)
            await broadcaster.shutdown()

            #expect(frames.isEmpty)
            // Belt-and-suspenders: `atLeast: 0` exits the poll loop
            // immediately, so without the subscribe-count check a
            // mistakenly-started routing task might still slip through.
            #expect(await source.subscribeCount == 0)
            #expect(await broadcaster.state == .playback(mode))
        }
    }

    @Test func multipleFrames_preservedInOrder() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let source = HoldingCameraSource(emitting: presets)
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let frames = await collectFrames(from: sink, atLeast: 3)
            await broadcaster.shutdown()

            #expect(frames.count == 3)
            #expect(frames.map(\.presentationTime) == [0.0, 0.1, 0.2])
            #expect(frames.map { $0.data.first } == [0x01, 0x02, 0x03])
        }
    }

    @Test func sourceThatFinishesNaturally_completesRoutingCleanly() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0), Self.frame(0.1)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let frames = await collectFrames(from: sink, atLeast: 2)
            await broadcaster.shutdown()

            #expect(frames.count == 2)
        }
    }

    // MARK: - State Transitions

    @Test func startDecoy_stopsRouting() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let initial = await collectFrames(from: sink, atLeast: 1)
            #expect(initial.count == 1)

            await broadcaster.handle(.startDecoy(.once))
            #expect(await broadcaster.state == .playback(.once))

            // Emit more frames after stopping routing — they must not reach sink.
            await source.append([Self.frame(0.1), Self.frame(0.2)])
            for _ in 0..<8 { await Task.yield() }

            let after = await sink.frames
            #expect(after.count == 1)
            await broadcaster.shutdown()
        }
    }

    @Test func returnToLive_resumesRouting() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            // No frames yet — routing not active. The empty-frames
            // check alone is weak (atLeast: 0 short-circuits the poll),
            // so pin the precondition via subscribeCount too.
            let beforeReturn = await collectFrames(from: sink, atLeast: 0)
            #expect(beforeReturn.isEmpty)
            #expect(await source.subscribeCount == 0)

            await broadcaster.handle(.returnToLive)
            let frames = await collectFrames(from: sink, atLeast: 1)
            await broadcaster.shutdown()

            #expect(frames.count == 1)
            #expect(await broadcaster.state == .live)
        }
    }

    @Test(arguments: [AppCommand.startRecording, .stopRecording])
    func foreignCommand_doesNotAffectRouting(foreign: AppCommand) async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let initial = await collectFrames(from: sink, atLeast: 1)
            #expect(initial.count == 1)

            await broadcaster.handle(foreign)
            await source.append([Self.frame(0.1)])
            let after = await collectFrames(from: sink, atLeast: 2)
            await broadcaster.shutdown()

            #expect(after.count == 2)
            #expect(await broadcaster.state == .live)
        }
    }

    // MARK: - Idempotency / Resource Hygiene

    @Test func returnToLive_whenAlreadyLive_doesNotDuplicateRouting() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            _ = await collectFrames(from: sink, atLeast: 1)

            await broadcaster.handle(.returnToLive)
            await broadcaster.handle(.returnToLive)
            await broadcaster.handle(.returnToLive)

            await source.append([Self.frame(0.1)])
            let frames = await collectFrames(from: sink, atLeast: 2)
            await broadcaster.shutdown()

            // Source must have been subscribed exactly once — repeated
            // returnToLive while already live is a no-op for routing.
            #expect(await source.subscribeCount == 1)
            #expect(frames.count == 2)
        }
    }

    @Test func startDecoy_whenAlreadyPlayback_doesNotRestartRouting() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            await broadcaster.handle(.startDecoy(.loop))
            await broadcaster.handle(.startDecoy(.pingPong))

            let frames = await collectFrames(from: sink, atLeast: 0)
            await broadcaster.shutdown()

            #expect(frames.isEmpty)
            #expect(await source.subscribeCount == 0)
        }
    }

    @Test func liveToPlaybackToLive_routingReSubscribesSource() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.virtualCameraSink = sink
            $0.clipStore = InMemoryClipStore()
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            _ = await collectFrames(from: sink, atLeast: 1)
            #expect(await source.subscribeCount == 1)

            await broadcaster.handle(.startDecoy(.once))
            await broadcaster.handle(.returnToLive)
            _ = await collectFrames(from: sink, atLeast: 1)
            await broadcaster.shutdown()

            // returnToLive after startDecoy must call source.frames() again.
            #expect(await source.subscribeCount == 2)
        }
    }
}

// MARK: - Test Helpers

extension BroadcasterIntegrationTests {

    /// Wait for at least `count` frames to arrive in the sink, then run a
    /// few extra yield cycles so any surplus arrivals surface in
    /// assertions. Tasks scheduled across actor boundaries vary in their
    /// yield-count to settle, so we poll first (up to `maxPolls`) instead
    /// of relying on a fixed budget. Returns the sink's full frame
    /// buffer after the settle window.
    private func collectFrames(
        from sink: InMemoryVirtualCameraSink,
        atLeast count: Int
    ) async -> [Frame] {
        let maxPolls = 100
        for _ in 0..<maxPolls {
            let current = await sink.frames
            if current.count >= count { break }
            await Task.yield()
        }
        for _ in 0..<4 { await Task.yield() }
        return await sink.frames
    }
}

// MARK: - Test Doubles

/// CameraSource that emits the preset frames and keeps the stream open
/// until consumer cancellation. Lets tests append more frames after
/// initial yield via `append(_:)`, enabling deterministic mid-recording
/// scenarios (subscribe → emit → state change → emit more → assert).
private actor HoldingCameraSource {
    private(set) var subscribeCount = 0
    private var continuations: [UUID: AsyncStream<Frame>.Continuation] = [:]
    private let preset: [Frame]

    init(emitting frames: [Frame]) {
        self.preset = frames
    }

    func append(_ frames: [Frame]) {
        continuations.values.forEach { continuation in
            frames.forEach { _ = continuation.yield($0) }
        }
    }

    private func unregister(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

extension HoldingCameraSource: CameraSource {
    func frames() async -> AsyncStream<Frame> {
        subscribeCount += 1
        let id = UUID()
        let (stream, continuation) = AsyncStream.makeStream(of: Frame.self)
        preset.forEach { _ = continuation.yield($0) }
        continuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.unregister(id: id) }
        }
        return stream
    }
}
