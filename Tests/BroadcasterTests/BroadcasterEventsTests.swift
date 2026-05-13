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
@testable import Broadcaster

@Suite("BroadcasterEvents", .timeLimit(.minutes(1)))
struct BroadcasterEventsTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    private static func clip(frames: [Frame]) -> Clip {
        let duration = (frames.last?.presentationTime ?? 0) - (frames.first?.presentationTime ?? 0)
        return Clip(id: UUID(), recordedAt: Self.fixedDate, frames: frames, duration: duration)
    }

    private static func seededStore(_ clips: [Clip]) async throws -> InMemoryClipStore {
        let store = InMemoryClipStore()
        for clip in clips { try await store.save(clip) }
        return store
    }

    // MARK: - .sendFailed (Live mode)

    @Test func liveMode_whenSinkThrows_emitsSendFailed() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "device busy"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 1)
            await broadcaster.shutdown()

            #expect(events.count >= 1)
            guard case .sendFailed = try #require(events.first) else {
                Issue.record("expected .sendFailed, got \(events[0])")
                return
            }
        }
    }

    @Test func liveMode_sendFailedEvent_carriesOriginalError() async throws {
        let expected = TestError(label: "broken pipe")
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingVirtualCameraSink(error: expected)

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 1)
            await broadcaster.shutdown()

            guard case .sendFailed(let observed) = try #require(events.first) else {
                Issue.record("expected .sendFailed, got \(events[0])")
                return
            }
            #expect((observed as? TestError) == expected)
        }
    }

    @Test func liveMode_multipleFrameFailures_emitMultipleSendFailedInOrder() async throws {
        // Live source emits 3 frames sequentially; sink throws on each.
        // Each failure must surface as its own event — routing must NOT
        // bail on the first error.
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let source = InMemoryCameraSource(emitting: frames)
        let sink = FailingVirtualCameraSink(error: TestError(label: "burst"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 3)
            await broadcaster.shutdown()

            #expect(events.count >= 3)
            let sendFailedCount = events.filter {
                if case .sendFailed = $0 { return true }
                return false
            }.count
            #expect(sendFailedCount >= 3)
        }
    }

    // MARK: - .sendFailed (Playback mode)

    @Test func playbackMode_whenSinkThrows_emitsSendFailedAndContinues() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "playback sink down"))

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 3)
            await broadcaster.shutdown()

            // .once with 3 frames → 3 .sendFailed (one per frame) — playback
            // continues past failures.
            let sendFailedCount = events.filter {
                if case .sendFailed = $0 { return true }
                return false
            }.count
            #expect(sendFailedCount >= 3)
        }
    }

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func playbackMode_acrossAllModes_emitsSendFailedOnSinkError(mode: PlaybackMode) async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "mode=\(mode)"))

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(mode))
            let events = await collectEvents(from: broadcaster, atLeast: 2)
            await broadcaster.shutdown()

            let sendFailedCount = events.filter {
                if case .sendFailed = $0 { return true }
                return false
            }.count
            #expect(sendFailedCount >= 2)
        }
    }

    // MARK: - .storeReadFailed (Playback only)

    @Test func playbackInit_whenStoreReadThrows_emitsStoreReadFailedOnce() async throws {
        let store = FailingClipStore(onAll: TestError(label: "store corrupt"))
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 1)
            await broadcaster.shutdown()

            let storeReadFailedCount = events.filter {
                if case .storeReadFailed = $0 { return true }
                return false
            }.count
            #expect(storeReadFailedCount == 1)
        }
    }

    @Test func storeReadFailedEvent_carriesOriginalError() async throws {
        let expected = TestError(label: "permission denied")
        let store = FailingClipStore(onAll: expected)
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 1)
            await broadcaster.shutdown()

            guard case .storeReadFailed(let observed) = try #require(events.first) else {
                Issue.record("expected .storeReadFailed, got \(events[0])")
                return
            }
            #expect((observed as? TestError) == expected)
        }
    }

    @Test func storeReadFailure_routingTerminates_subsequentStartDecoyRetries() async throws {
        // After a .storeReadFailed, routing exits naturally (no clip
        // to play). The same-mode-after-dead-routing replay path
        // (added in bad3ced) must trigger another store read, which
        // emits a second .storeReadFailed.
        let store = FailingClipStore(onAll: TestError(label: "again"))
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 2) {
                // First .storeReadFailed flows during the init's routing
                // task. Burn yields so it surfaces before we issue the
                // retry — otherwise the second startDecoy could race the
                // first one's read.
                for _ in 0..<200 { await Task.megaYield() }
                await broadcaster.handle(.startDecoy(.once))
            }
            await broadcaster.shutdown()

            let storeReadFailedCount = events.filter {
                if case .storeReadFailed = $0 { return true }
                return false
            }.count
            #expect(storeReadFailedCount >= 2)
        }
    }

    @Test func liveMode_withFailingClipStore_emitsNoStoreReadFailed() async throws {
        // Live mode never reads the store, so a failing store must
        // emit no .storeReadFailed.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = FailingClipStore(onAll: TestError(label: "unused"))
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            let storeReadFailedCount = events.filter {
                if case .storeReadFailed = $0 { return true }
                return false
            }.count
            #expect(storeReadFailedCount == 0)
        }
    }

    // MARK: - Cancellation suppression

    @Test func liveMode_sinkThrowsCancellationError_emitsNoSendFailed() async throws {
        // sink.send may throw CancellationError when the routing task is
        // cancelled mid-flight (shutdown / state transition). This is
        // not a real failure — surfacing it as .sendFailed would be
        // noise. Verify suppression.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingVirtualCameraSink(error: CancellationError())

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    @Test func playbackMode_sinkThrowsCancellationError_emitsNoSendFailed() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = FailingVirtualCameraSink(error: CancellationError())

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    @Test func shutdownBeforeInitialRouting_emitsNoEvents() async throws {
        // init defers `startRouting()` via a `Task { await self?... }`
        // hop so the emit closure can capture fully-initialized self.
        // A caller that does `Broadcaster() → await shutdown()` rapidly
        // can race the deferred hop — without a sticky `terminated`
        // flag, `stopRouting()` would see `routing == nil`, return, and
        // then the deferred task could still start routing afterward.
        // Verify the shutdown contract: after `shutdown()` completes,
        // no events emit regardless of init-task ordering.
        let sink = FailingVirtualCameraSink(error: TestError(label: "race"))
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            await broadcaster.shutdown()
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            #expect(events.isEmpty)
        }
    }

    @Test func handleAfterShutdown_doesNotRestartRouting() async throws {
        // Once shutdown has run, `handle(.startDecoy)` / `.returnToLive`
        // must be a no-op — otherwise callers could resurrect routing
        // after intentional shutdown.
        let presets = [Self.frame(0.0, 0x01)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "post-shutdown"))

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            await broadcaster.shutdown()
            let events = await collectEvents(from: broadcaster, atLeast: 0) {
                await broadcaster.handle(.startDecoy(.loop))
                await broadcaster.handle(.returnToLive)
            }
            #expect(events.isEmpty)
        }
    }

    @Test func playbackMode_storeThrowsCancellationError_emitsNoStoreReadFailed() async throws {
        // CancellationError on store.all() during playback init must be
        // suppressed — same rationale as sink cancellation.
        let store = FailingClipStore(onAll: CancellationError())
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    // MARK: - No-event scenarios

    @Test func liveMode_withSuccessfulSink_emitsNoEvents() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    @Test func playbackMode_withSuccessfulSinkAndStore_emitsNoEvents() async throws {
        let presets = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    @Test func playbackMode_withEmptyStore_emitsNoEvents() async throws {
        // Empty store is distinct from a failing store: the existing
        // "silent no-op" behavior must be preserved — no
        // .storeReadFailed for empty.
        let store = InMemoryClipStore()
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .playback(.once))
            let events = await collectEvents(from: broadcaster, atLeast: 0)
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    @Test(arguments: [AppCommand.startRecording, .stopRecording])
    func recordingCommand_emitsNoBroadcasterEvent(foreign: AppCommand) async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let sink = InMemoryVirtualCameraSink()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let events = await collectEvents(from: broadcaster, atLeast: 0) {
                await broadcaster.handle(foreign)
            }
            await broadcaster.shutdown()

            #expect(events.isEmpty)
        }
    }

    // MARK: - Multi-subscriber broadcast

    @Test func twoSubscribersBeforeRouting_bothReceiveSendFailed() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "multi"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster(state: .live)
            // Subscribe BEFORE routing emits events (state is .live but
            // we control timing via HoldingCameraSource? Actually for
            // InMemoryCameraSource the source finishes quickly so we
            // need to subscribe before any send happens).
            let firstSub = await broadcaster.subscribeEvents()
            let secondSub = await broadcaster.subscribeEvents()

            async let firstEvents: [Broadcaster.Event] = take(firstSub, count: 1)
            async let secondEvents: [Broadcaster.Event] = take(secondSub, count: 1)

            // Force the routing task forward by yielding.
            await Task.megaYield()

            let aResult = await firstEvents
            let bResult = await secondEvents
            await broadcaster.shutdown()

            #expect(aResult.count == 1)
            #expect(bResult.count == 1)
            guard case .sendFailed = try #require(aResult.first),
                  case .sendFailed = try #require(bResult.first)
            else {
                Issue.record("expected both subscribers to receive .sendFailed")
                return
            }
        }
    }

    @Test func subscriberAddedMidRouting_receivesLaterEvents() async throws {
        // Live source kept open via HoldingCameraSource — we can
        // subscribe after the first frame's failure and still see the
        // next frame's failure event.
        let source = HoldingEventCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "late"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            // Let the first frame fail.
            await Task.megaYield()

            let lateSub = await broadcaster.subscribeEvents()
            async let lateEvents: [Broadcaster.Event] = take(lateSub, count: 1)

            // Append more frames — these will also fail and the late
            // subscriber must see at least one.
            await source.append([Self.frame(0.1, 0xBB)])
            await Task.megaYield()

            let observed = await lateEvents
            await broadcaster.shutdown()

            #expect(observed.count == 1)
            guard case .sendFailed = try #require(observed.first) else {
                Issue.record("expected late subscriber to receive a .sendFailed")
                return
            }
        }
    }

    @Test func subscriberCancellation_doesNotAffectOtherSubscriber() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "isolation"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()

            let persistentSub = await broadcaster.subscribeEvents()
            let cancelledSub = await broadcaster.subscribeEvents()

            async let persistentEvents: [Broadcaster.Event] = take(persistentSub, count: 1)
            let doomed = Task<[Broadcaster.Event], Never> { [cancelledSub] in
                await take(cancelledSub, count: 1)
            }
            doomed.cancel()
            _ = await doomed.value

            await Task.megaYield()

            let observed = await persistentEvents
            await broadcaster.shutdown()

            #expect(observed.count == 1)
            guard case .sendFailed = try #require(observed.first) else {
                Issue.record("expected persistent subscriber to still receive .sendFailed")
                return
            }
        }
    }

    // MARK: - Lifetime / state-transition independence

    @Test func subscriber_survivesAcrossStateTransitions() async throws {
        // A single subscriber observes events that originate from
        // both the Live phase and the Playback phase of the same
        // Broadcaster lifetime — the subscriber list isn't tied to a
        // single routing task.
        let liveSource = InMemoryCameraSource(emitting: [Self.frame(0.0, 0xAA)])
        let presets = [Self.frame(0.0, 0x11)]
        let store = try await Self.seededStore([Self.clip(frames: presets)])
        let sink = FailingVirtualCameraSink(error: TestError(label: "cross-phase"))

        try await withDependencies {
            $0.cameraSource = liveSource
            $0.clipStore = store
            $0.virtualCameraSink = sink
            $0.continuousClock = ImmediateClock()
        } operation: {
            let broadcaster = Broadcaster()
            let subscription = await broadcaster.subscribeEvents()
            async let events: [Broadcaster.Event] = take(subscription, count: 2)

            await Task.megaYield()  // live frame fails → .sendFailed (1)
            await broadcaster.handle(.startDecoy(.once))
            await Task.megaYield()  // playback frame fails → .sendFailed (2)

            let observed = await events
            await broadcaster.shutdown()

            #expect(observed.count == 2)
            for event in observed {
                guard case .sendFailed = event else {
                    Issue.record("expected all .sendFailed, got \(event)")
                    return
                }
            }
        }
    }
}

// MARK: - Test Helpers

extension BroadcasterEventsTests {

    /// Subscribe and collect events emitted during the broadcaster's
    /// operation. Polls until `count` events are observed or the budget
    /// is exhausted. For `atLeast: 0` (negative-assertion tests) we still
    /// burn a small settle window so the routing task has a chance to
    /// emit anything it would emit. megaYield matches `ImmediateClock`'s
    /// internal scheduling — see `BroadcasterPlaybackTests.collectFrames`
    /// for rationale.
    private func collectEvents(
        from broadcaster: Broadcaster,
        atLeast count: Int,
        while action: (@Sendable () async -> Void)? = nil
    ) async -> [Broadcaster.Event] {
        let subscription = await broadcaster.subscribeEvents()
        let buffer = EventBuffer()
        let collector = Task<Void, Never> { [subscription] in
            for await event in subscription {
                await buffer.append(event)
            }
        }
        if let action { await action() }
        let minSettle = 5
        let maxBudget = 200
        for iteration in 0..<maxBudget {
            await Task.megaYield()
            if iteration >= minSettle, await buffer.count >= count { break }
        }
        await Task.megaYield()
        collector.cancel()
        return await buffer.snapshot
    }

    private func take(_ subscription: Broadcaster.Subscription, count: Int) async -> [Broadcaster.Event] {
        var collected: [Broadcaster.Event] = []
        for await event in subscription {
            collected.append(event)
            if collected.count >= count { break }
        }
        return collected
    }
}

// MARK: - Test Doubles

private struct TestError: Error, Equatable, Sendable {
    let label: String
}

/// Shared event sink for `collectEvents`. Lives on its own actor so the
/// polling loop can peek at the captured count without racing the
/// collector's append path.
private actor EventBuffer {
    private var events: [Broadcaster.Event] = []

    func append(_ event: Broadcaster.Event) {
        events.append(event)
    }

    var count: Int { events.count }
    var snapshot: [Broadcaster.Event] { events }
}

/// VirtualCameraSink that always throws the given error on send.
private actor FailingVirtualCameraSink {
    private let error: any Error & Sendable
    private(set) var sendCallCount = 0

    init(error: any Error & Sendable) {
        self.error = error
    }
}

extension FailingVirtualCameraSink: VirtualCameraSink {
    func send(_ frame: Frame) async throws {
        sendCallCount += 1
        throw error
    }
}

/// ClipStore that throws the given error on `all()` (the playback
/// read path). `save` and `clip(id:)` are stubbed to no-op / nil since
/// playback only exercises `all()`.
private actor FailingClipStore {
    private let allError: any Error & Sendable

    init(onAll error: any Error & Sendable) {
        self.allError = error
    }
}

extension FailingClipStore: ClipStore {
    func save(_ clip: Clip) async throws {}
    func all() async throws -> [Clip] { throw allError }
    func clip(id: UUID) async throws -> Clip? { nil }
    func delete(id: UUID) async throws {}
}

/// CameraSource that emits preset frames then holds the stream open,
/// allowing tests to append more frames after subscribe. Mirrors the
/// shape used in `BroadcasterIntegrationTests.HoldingCameraSource` but
/// kept private to this file to avoid cross-file private collisions.
private actor HoldingEventCameraSource {
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

extension HoldingEventCameraSource: CameraSource {
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
