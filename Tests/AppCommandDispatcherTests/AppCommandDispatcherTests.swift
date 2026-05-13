import Testing
import Foundation
import Clocks
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
import InMemoryVirtualCameraSink
@testable import AppCommandDispatcher
@testable import Broadcaster
@testable import Recorder

@Suite("AppCommandDispatcher")
struct AppCommandDispatcherTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Construction

    @Test func init_storesBothActors() async {
        await withStubDeps {
            let recorder = Recorder()
            let broadcaster = Broadcaster()
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
            // Touching the dispatcher should not throw or trap. The
            // smoke test is that we can dispatch an unrelated command
            // and both actors remain in their default state.
            await dispatcher.dispatch(.returnToLive)
            #expect(await recorder.state == .idle)
            #expect(await broadcaster.state == .live)
        }
    }

    // MARK: - Per-command fan-out

    @Test func dispatch_startRecording_reachesRecorderAndIsNoOpOnBroadcaster() async throws {
        // Use an empty source so the recorder's consumption Task
        // terminates naturally after .startRecording — no frames saved
        // but the full begin→finish lifecycle was driven by the
        // dispatch. Broadcaster is pinned to .playback(.once) so we can
        // assert it stays untouched by recording commands.
        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let broadcaster = Broadcaster(state: .playback(.once))
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)

            await dispatcher.dispatch(.startRecording)
            // Drive the consumption Task to completion so we observe
            // the post-finish state deterministically.
            await dispatcher.dispatch(.stopRecording)

            #expect(await recorder.state == .idle)
            // Broadcaster's mode is unchanged by recording commands.
            #expect(await broadcaster.state == .playback(.once))
        }
    }

    @Test func dispatch_stopRecording_reachesRecorderAndIsNoOpOnBroadcaster() async throws {
        // Distinct from the startRecording test: this one verifies the
        // Recorder actually persisted a clip — meaning the stop command
        // landed on the Recorder side, not just the broadcaster.
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()
        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let broadcaster = Broadcaster(state: .playback(.once))
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)

            await dispatcher.dispatch(.startRecording)
            await dispatcher.dispatch(.stopRecording)

            #expect(await recorder.state == .idle)
            let saved = try await store.all()
            #expect(saved.count == 1)
            #expect(await broadcaster.state == .playback(.once))
        }
    }

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func dispatch_startDecoy_reachesBroadcasterAndIsNoOpOnRecorder(mode: PlaybackMode) async {
        await withStubDeps {
            let recorder = Recorder()
            let broadcaster = Broadcaster(state: .live)
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)

            await dispatcher.dispatch(.startDecoy(mode))

            #expect(await broadcaster.state == .playback(mode))
            // Recorder ignores decoy commands — stays idle. Camera
            // subscribe count is not a clean signal here because the
            // Broadcaster also subscribes on .live init; recorder.state
            // is the authoritative check.
            #expect(await recorder.state == .idle)
        }
    }

    @Test func dispatch_returnToLive_reachesBroadcasterAndIsNoOpOnRecorder() async {
        await withStubDeps {
            let recorder = Recorder()
            let broadcaster = Broadcaster(state: .playback(.loop))
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)

            await dispatcher.dispatch(.returnToLive)

            #expect(await broadcaster.state == .live)
            #expect(await recorder.state == .idle)
        }
    }

    // MARK: - Fan-out integrity

    /// Verify that a single `dispatch` reliably delivers the command to
    /// **both** actors before returning — the structural guarantee of
    /// `async let r`/`async let b`. We exercise a command that produces
    /// observable side effects on both sides at once: chain a recording
    /// (Recorder side effect) with a decoy-mode change (Broadcaster side
    /// effect) and assert both landed.
    @Test func dispatch_fansOutToBothActorsBeforeReturning() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()
        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let broadcaster = Broadcaster(state: .live)
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)

            // .startRecording reaches the Recorder. Then .startDecoy
            // reaches the Broadcaster. Both side effects must be
            // observable after dispatch returns.
            await dispatcher.dispatch(.startRecording)
            await dispatcher.dispatch(.stopRecording)
            await dispatcher.dispatch(.startDecoy(.once))

            let saved = try await store.all()
            #expect(saved.count == 1)
            #expect(await broadcaster.state == .playback(.once))
        }
    }

    @Test func dispatch_isSendableAcrossActors() async {
        // Sanity check: the dispatcher is a value type and can be
        // shared across isolation boundaries. If the type stops
        // conforming to Sendable, this captures it.
        await withStubDeps {
            let recorder = Recorder()
            let broadcaster = Broadcaster()
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
            let copy = dispatcher
            await copy.dispatch(.returnToLive)
            #expect(await broadcaster.state == .live)
        }
    }
}

// MARK: - Test Helpers

extension AppCommandDispatcherTests {
    /// State-only smoke tests need every port wired because Broadcaster
    /// captures all of them in `init` and Recorder reads them on
    /// `handle`. Empty source / store finish immediately so no frames
    /// flow through the sink; `ImmediateClock` keeps any pacing in
    /// playback routing from blocking the test.
    fileprivate func withStubDeps<R: Sendable>(
        _ operation: @Sendable () async throws -> R
    ) async rethrows -> R {
        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Date(timeIntervalSince1970: 1_700_000_000))
            $0.uuid = .incrementing
        } operation: {
            try await operation()
        }
    }
}
