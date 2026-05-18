import Testing
import Foundation
import Clocks
import ConcurrencyExtras
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
import InMemoryVirtualCameraSink
@testable import BroadcasterUseCase

@Suite("BroadcasterPlayback", .timeLimit(.minutes(1)))
struct BroadcasterPlaybackTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8) -> Frame {
        Frame(presentationTime: pts, pixelData: Data(repeating: byte, count: 64), width: 4, height: 4, pixelFormat: 0x42475241, bytesPerRow: 16)
    }

    private static func clip(
        id: UUID = UUID(),
        recordedAt: Date = Self.fixedDate,
        frames: [Frame]
    ) -> Clip {
        let duration = (frames.last?.presentationTime ?? 0) - (frames.first?.presentationTime ?? 0)
        return Clip(id: id, recordedAt: recordedAt, frames: frames, duration: duration)
    }

    private static func seededStore(_ clips: [Clip]) async throws -> InMemoryClipStore {
        let store = InMemoryClipStore()
        for clip in clips { try await store.save(clip) }
        return store
    }

    // MARK: - Playback source

    @Test func playbackInit_withClipInStore_emitsClipFramesToSink() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            let frames = await collectFrames(from: sink, atLeast: 3)
            await broadcaster.shutdown()

            #expect(frames.count == 3)
            #expect(frames.map(\.presentationTime) == [0.0, 0.1, 0.2])
            #expect(frames.map { $0.pixelData.first } == [0x01, 0x02, 0x03])
        }
    }

    @Test func playbackInit_withEmptyStore_routesNothing() async {
        let store = InMemoryClipStore()
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            let frames = await collectFrames(from: sink, atLeast: 0)
            await broadcaster.shutdown()

            #expect(frames.isEmpty)
            #expect(await broadcaster.state == .playback(.once))
        }
    }

    @Test func playbackInit_picksLatestClipByRecordedAt() async throws {
        let older = Self.clip(
            recordedAt: Self.fixedDate,
            frames: [Self.frame(0.0, 0xAA)]
        )
        let newer = Self.clip(
            recordedAt: Self.fixedDate.addingTimeInterval(60),
            frames: [Self.frame(0.0, 0xBB), Self.frame(0.1, 0xCC)]
        )
        let store = try await Self.seededStore([older, newer])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            let frames = await collectFrames(from: sink, atLeast: 2)
            await broadcaster.shutdown()

            #expect(frames.map { $0.pixelData.first } == [0xBB, 0xCC])
        }
    }

    // MARK: - PlaybackMode semantics

    @Test func onceMode_terminatesAfterLastFrame() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            let frames = await collectFrames(from: sink, atLeast: 2)
            // Settle and ensure no more frames arrive after the last preset.
            for _ in 0..<20 { await Task.yield() }
            let stable = await sink.frames
            await broadcaster.shutdown()

            #expect(frames.count == 2)
            #expect(stable.count == 2)
        }
    }

    @Test func loopMode_emitsFramesRepeatedly() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.loop))
            let frames = await collectFrames(from: sink, atLeast: 9)
            await broadcaster.shutdown()

            // First 9 frames: 3 cycles of [0x01, 0x02, 0x03].
            let firstNine = Array(frames.prefix(9)).map { $0.pixelData.first }
            #expect(firstNine == [0x01, 0x02, 0x03, 0x01, 0x02, 0x03, 0x01, 0x02, 0x03])
        }
    }

    @Test func pingPongMode_emitsForwardThenReverseWithoutEndpointDuplication() async throws {
        // Pattern (no endpoint duplication): A B C B A B C B A ...
        let presets = [Self.frame(0.0, 0xA0), Self.frame(0.1, 0xB0), Self.frame(0.2, 0xC0)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.pingPong))
            let frames = await collectFrames(from: sink, atLeast: 9)
            await broadcaster.shutdown()

            let firstNine = Array(frames.prefix(9)).map { $0.pixelData.first }
            #expect(firstNine == [0xA0, 0xB0, 0xC0, 0xB0, 0xA0, 0xB0, 0xC0, 0xB0, 0xA0])
        }
    }

    @Test func pingPongMode_singleFrameClip_emitsThatFrameRepeatedly() async throws {
        // Edge case: 1-frame clip has no "direction" to swap. Just keep
        // emitting the single frame.
        let presets = [Self.frame(0.0, 0x55)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.pingPong))
            let frames = await collectFrames(from: sink, atLeast: 5)
            await broadcaster.shutdown()

            let firstFive = Array(frames.prefix(5)).map { $0.pixelData.first }
            #expect(firstFive == [0x55, 0x55, 0x55, 0x55, 0x55])
        }
    }

    // MARK: - Inter-frame gap (loop wrap-around)

    @Test func gapBetween_loopWrap_snapsToMinimumGap() async {
        // Loop wrap (last → first): using abs(pts delta) would yield
        // ~duration and stall the cycle boundary. Verify the wrap
        // returns the minimum gap instead so loop period stays ~duration,
        // not 2 × duration.
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let gap = BroadcasterUseCaseImpl.gapBetween(current: 2, next: 0, frames: frames, mode: .loop)

        #expect(gap == 0.001)
    }

    @Test func gapBetween_loopForward_usesPtsDelta() async {
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let gap = BroadcasterUseCaseImpl.gapBetween(current: 0, next: 1, frames: frames, mode: .loop)

        // (0.1 - 0.0) within float tolerance
        #expect(abs(gap - 0.1) < 1e-9)
    }

    @Test func gapBetween_onceForward_usesPtsDelta() async {
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.5, 0x02)]
        let gap = BroadcasterUseCaseImpl.gapBetween(current: 0, next: 1, frames: frames, mode: .once)

        #expect(abs(gap - 0.5) < 1e-9)
    }

    @Test func gapBetween_pingPongReverse_usesPtsDelta() async {
        // PingPong reverse step (2 → 1) is still a physical-neighbour
        // transition — gap should be the pts delta, NOT minimumFrameGap.
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let gap = BroadcasterUseCaseImpl.gapBetween(current: 2, next: 1, frames: frames, mode: .pingPong)

        #expect(abs(gap - 0.1) < 1e-9)
    }

    @Test func gapBetween_zeroDelta_flooredToMinimum() async {
        // Identical pts (degenerate clip) must not return 0 — that would
        // hot-spin the routing task.
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.0, 0x02)]
        let gap = BroadcasterUseCaseImpl.gapBetween(current: 0, next: 1, frames: frames, mode: .loop)

        #expect(gap == 0.001)
    }

    // MARK: - State Transitions

    @Test func liveToPlayback_cancelsLiveRoutingAndStartsPlayback() async throws {
        let livePresets = [Self.frame(0.0, 0xAA)]
        let liveSource = HoldingCameraSource(emitting: livePresets)
        let clipPresets = [Self.frame(0.0, 0x11), Self.frame(0.1, 0x22)]
        let store = try await Self.seededStore([Self.clip(frames: clipPresets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = liveSource
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl()
            // Live frames come through first.
            let live = await collectFrames(from: sink, atLeast: 1)
            #expect(live.count == 1)
            #expect(live.first.flatMap { $0.pixelData.first } == 0xAA)

            await broadcaster.handle(.startDecoy(.once))

            // Wait for clip frames (total = 1 live + 2 clip).
            let combined = await collectFrames(from: sink, atLeast: 3)
            await broadcaster.shutdown()

            #expect(combined.count == 3)
            #expect(combined.map { $0.pixelData.first } == [0xAA, 0x11, 0x22])
            #expect(await broadcaster.state == .playback(.once))
        }
    }

    @Test func playbackToLive_cancelsPlaybackAndResumesLiveRouting() async throws {
        let liveSource = HoldingCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let clipPresets = [Self.frame(0.0, 0x11), Self.frame(0.1, 0x22), Self.frame(0.2, 0x33)]
        let store = try await Self.seededStore([Self.clip(frames: clipPresets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = liveSource
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.loop))
            let beforeReturn = await collectFrames(from: sink, atLeast: 3)
            #expect(beforeReturn.count >= 3)

            await broadcaster.handle(.returnToLive)
            // Wait until live routing has subscribed to liveSource —
            // otherwise the upcoming `append(0xBB)` would yield to zero
            // continuations and the marker would never reach the sink.
            for _ in 0..<200 {
                if await liveSource.subscribeCount > 0 { break }
                await Task.megaYield()
            }
            // Append a fresh live frame so we can prove live is routing.
            await liveSource.append([Self.frame(1.0, 0xBB)])

            // Collect until we see the live marker. `megaYield` matches
            // `ImmediateClock.sleep`'s internal scheduling — the playback
            // cancellation drain plus live resubscribe ride on
            // background-priority detached tasks.
            var settled: [Frame] = []
            for _ in 0..<200 {
                settled = await sink.frames
                if settled.contains(where: { $0.pixelData.first == 0xBB }) { break }
                await Task.megaYield()
            }
            await broadcaster.shutdown()

            #expect(settled.contains(where: { $0.pixelData.first == 0xAA }))
            #expect(settled.contains(where: { $0.pixelData.first == 0xBB }))
            #expect(await broadcaster.state == .live)
        }
    }

    // MARK: - Restart after natural completion

    @Test func onceMode_naturalCompletion_thenStartDecoySameMode_replaysClip() async throws {
        // After `.once` plays its last frame, routing exits naturally
        // (routing == nil) while state stays `.playback(.once)`. A second
        // `startDecoy(.once)` must replay the clip, not be a no-op —
        // otherwise users can't repeat playback without bouncing through
        // .returnToLive.
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            let first = await collectFrames(from: sink, atLeast: 2)
            #expect(first.count == 2)

            await broadcaster.handle(.startDecoy(.once))
            let total = await collectFrames(from: sink, atLeast: 4)
            await broadcaster.shutdown()

            #expect(total.count == 4)
            #expect(total.map { $0.pixelData.first } == [0x01, 0x02, 0x01, 0x02])
        }
    }

    @Test func emptyStoreAtInit_thenAddClip_andStartDecoySameMode_replays() async throws {
        // Empty store at init → playback routing exits immediately
        // (routing == nil). After saving a clip, a fresh
        // `startDecoy(sameMode)` must pick it up instead of being a
        // no-op against the stale state.
        let store = InMemoryClipStore()
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            let initial = await collectFrames(from: sink, atLeast: 0)
            #expect(initial.isEmpty)

            try await store.save(Self.clip(frames: [Self.frame(0.0, 0xAA), Self.frame(0.1, 0xBB)]))
            await broadcaster.handle(.startDecoy(.once))
            let after = await collectFrames(from: sink, atLeast: 2)
            await broadcaster.shutdown()

            #expect(after.map { $0.pixelData.first } == [0xAA, 0xBB])
        }
    }

    @Test func shutdown_duringLoopPlayback_stopsFurtherEmissions() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.loop))
            _ = await collectFrames(from: sink, atLeast: 6)
            await broadcaster.shutdown()

            // After shutdown, no further frames should arrive.
            let snapshot = await sink.frames
            for _ in 0..<20 { await Task.yield() }
            let later = await sink.frames

            #expect(later.count == snapshot.count)
        }
    }

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func playbackInit_emptyStore_acrossAllModes(mode: PlaybackMode) async {
        let store = InMemoryClipStore()
        let sink = InMemoryVirtualCameraSink()

        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(mode))
            let frames = await collectFrames(from: sink, atLeast: 0)
            await broadcaster.shutdown()

            #expect(frames.isEmpty)
        }
    }
}

// MARK: - Test Helpers

extension BroadcasterPlaybackTests {

    /// Poll the sink until at least `count` frames arrive (or `maxPolls`
    /// elapse), then take an extra megaYield so surplus arrivals surface in
    /// assertions. `Task.megaYield()` matches `ImmediateClock.sleep`'s
    /// internal scheduling mechanism (20 background-priority detached
    /// `Task.yield()` calls) — without it, frame-emission tasks scheduled
    /// at background priority don't get a chance to run between polls.
    private func collectFrames(
        from sink: InMemoryVirtualCameraSink,
        atLeast count: Int
    ) async -> [Frame] {
        let maxPolls = 200
        for _ in 0..<maxPolls {
            let current = await sink.frames
            if current.count >= count { break }
            await Task.megaYield()
        }
        await Task.megaYield()
        return await sink.frames
    }
}

// MARK: - Test Doubles

/// Same `HoldingCameraSource` shape used in
/// `BroadcasterIntegrationTests` — keeps the live stream open so we can
/// inject more frames mid-test via `append(_:)`.
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
