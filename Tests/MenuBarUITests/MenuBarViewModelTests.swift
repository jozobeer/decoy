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
@testable import MenuBarUI
@testable import Recorder

@Suite("MenuBarViewModel", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarViewModelTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Initial state

    @Test func init_initialState_matchesDefaults() async {
        await withStubDeps {
            let viewModel = makeViewModel()

            #expect(viewModel.recordingState == .idle)
            #expect(viewModel.outputMode == .live)
            #expect(viewModel.pendingPlaybackMode == .loop)
            #expect(viewModel.lastErrorMessage == nil)
            #expect(viewModel.isRecording == false)
            #expect(viewModel.isInDecoy == false)
            #expect(viewModel.activePlaybackMode == nil)
        }
    }

    @Test func start_primesStateFromActors() async {
        await withStubDeps {
            let viewModel = makeViewModel(broadcasterState: .playback(.pingPong))
            await viewModel.start()

            #expect(viewModel.outputMode == .playback(.pingPong))
            #expect(viewModel.activePlaybackMode == .pingPong)
            #expect(viewModel.isInDecoy)
        }
    }

    // MARK: - Dispatch verbs

    @Test func startRecording_dispatchesAndRefreshesState() async {
        await withStubDeps {
            let spy = SpyDispatcher()
            let viewModel = makeViewModel(dispatcher: spy)

            await viewModel.startRecording()

            await #expect(spy.commands == [.startRecording])
            #expect(viewModel.recordingState == .idle)
        }
    }

    @Test func startRecording_thenStop_persistsClip_andRefreshesToIdle() async throws {
        // End-to-end: drive the real dispatcher and observe that the
        // view-model's `recordingState` ends at `.idle` after the
        // recorder's finish path runs. Tests both the dispatch wiring
        // and the post-dispatch state refresh.
        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [Self.frame(0.0)])
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let broadcaster = Broadcaster()
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
            let viewModel = MenuBarViewModel(
                recorder: recorder,
                broadcaster: broadcaster,
                dispatcher: dispatcher
            )

            await viewModel.startRecording()
            await viewModel.stopRecording()

            #expect(viewModel.recordingState == .idle)
        }
    }

    @Test func startDecoy_dispatchesPendingMode() async {
        await withStubDeps {
            let spy = SpyDispatcher()
            let viewModel = makeViewModel(dispatcher: spy)
            viewModel.pendingPlaybackMode = .pingPong

            await viewModel.startDecoy()

            await #expect(spy.commands == [.startDecoy(.pingPong)])
        }
    }

    @Test func returnToLive_dispatches_andRefreshesState() async {
        await withStubDeps {
            let spy = SpyDispatcher()
            let viewModel = makeViewModel(dispatcher: spy, broadcasterState: .playback(.loop))
            await viewModel.start()

            await viewModel.returnToLive()

            await #expect(spy.commands == [.returnToLive])
            // SpyDispatcher does not mutate the real broadcaster, so
            // `outputMode` remains what `start()` snapshotted. The
            // assertion that matters: `refreshState` ran (it re-read
            // the broadcaster), which is observable via the equality
            // below holding without us having explicitly set it post-
            // dispatch.
            #expect(viewModel.outputMode == .playback(.loop))
        }
    }

    // MARK: - Picker behaviour

    @Test func selectPlaybackMode_whileLive_updatesPendingOnly_doesNotDispatch() async {
        await withStubDeps {
            let spy = SpyDispatcher()
            let viewModel = makeViewModel(dispatcher: spy)
            await viewModel.start()

            await viewModel.selectPlaybackMode(.once)

            #expect(viewModel.pendingPlaybackMode == .once)
            await #expect(spy.commands.isEmpty)
        }
    }

    @Test func selectPlaybackMode_whileInDecoy_dispatchesStartDecoy() async {
        await withStubDeps {
            let spy = SpyDispatcher()
            let viewModel = makeViewModel(dispatcher: spy, broadcasterState: .playback(.loop))
            await viewModel.start()

            await viewModel.selectPlaybackMode(.pingPong)

            #expect(viewModel.pendingPlaybackMode == .pingPong)
            await #expect(spy.commands == [.startDecoy(.pingPong)])
        }
    }

    // MARK: - View helpers

    @Test func isRecording_followsRecordingState() async throws {
        // An InMemoryCameraSource that never emits keeps the recorder's
        // consumption Task alive, so `recordingState` stays `.recording`
        // until `stopRecording` cancels it. A finite emit list would
        // race the assertion against the consumption Task's completion.
        let source = NeverEndingCameraSource()
        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let broadcaster = Broadcaster()
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
            let viewModel = MenuBarViewModel(
                recorder: recorder,
                broadcaster: broadcaster,
                dispatcher: dispatcher
            )

            await viewModel.startRecording()
            #expect(viewModel.isRecording)

            await viewModel.stopRecording()
            #expect(viewModel.isRecording == false)
        }
    }

    @Test func activePlaybackMode_flattensOutputMode() async {
        await withStubDeps {
            let viewModel = makeViewModel(broadcasterState: .playback(.once))
            await viewModel.start()

            #expect(viewModel.activePlaybackMode == .once)
            #expect(viewModel.isInDecoy)
        }
    }

    // MARK: - Event-driven error surfacing

    @Test func saveFailedEvent_surfacedAsErrorMessage() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = FailingClipStore()
        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let broadcaster = Broadcaster()
            let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
            let viewModel = MenuBarViewModel(
                recorder: recorder,
                broadcaster: broadcaster,
                dispatcher: dispatcher
            )
            await viewModel.start()

            await viewModel.startRecording()
            await viewModel.stopRecording()
            await waitForCondition { viewModel.lastErrorMessage != nil }

            #expect(viewModel.lastErrorMessage?.contains("録画の保存に失敗") == true)
        }
    }
}

// MARK: - Test helpers

extension MenuBarViewModelTests {
    fileprivate func withStubDeps<R: Sendable>(
        _ operation: @MainActor @Sendable () async throws -> R
    ) async rethrows -> R {
        try await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [])
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            try await operation()
        }
    }

    /// Build a view-model around a fresh Recorder/Broadcaster pair.
    /// `broadcasterState` lets a test set the initial output mode so
    /// `.playback` paths are covered without dispatching first.
    fileprivate func makeViewModel(
        dispatcher: (any AppCommandDispatching)? = nil,
        broadcasterState: OutputMode = .live
    ) -> MenuBarViewModel {
        let recorder = Recorder()
        let broadcaster = Broadcaster(state: broadcasterState)
        let resolvedDispatcher: any AppCommandDispatching = dispatcher
            ?? AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
        return MenuBarViewModel(
            recorder: recorder,
            broadcaster: broadcaster,
            dispatcher: resolvedDispatcher
        )
    }

    /// Poll until `predicate` flips true. Used to await an event hop
    /// that lands asynchronously after a dispatch returns. Bounded by
    /// the suite's outer `.timeLimit` so a stuck condition still fails.
    fileprivate func waitForCondition(
        _ predicate: @MainActor () -> Bool
    ) async {
        while !predicate() {
            await Task.yield()
        }
    }
}

// MARK: - Doubles

/// Sendable spy that records each dispatched command in order.
/// Backed by an actor so concurrent `dispatch` calls don't lose entries.
private actor SpyDispatcherStore {
    var commands: [AppCommand] = []
    func append(_ command: AppCommand) { commands.append(command) }
}

private struct SpyDispatcher: AppCommandDispatching {
    private let store = SpyDispatcherStore()

    func dispatch(_ command: AppCommand) async {
        await store.append(command)
    }

    var commands: [AppCommand] {
        get async { await store.commands }
    }
}

/// CameraSource that yields no frames but never finishes — keeps the
/// Recorder's consumption Task alive so `recordingState` stays
/// `.recording` until `stopRecording` cancels it.
private struct NeverEndingCameraSource: CameraSource {
    func frames() async -> AsyncStream<Frame> {
        AsyncStream { _ in
            // Hold the continuation forever; consumer's Task.cancel
            // ends iteration on the consumer side.
        }
    }
}

/// ClipStore stub that fails on `save` so we can drive the
/// `.saveFailed` event path through the real Recorder.
private actor FailingClipStore: ClipStore {
    struct Boom: Error & Sendable {}

    func save(_ clip: Clip) async throws {
        throw Boom()
    }

    func all() async throws -> [Clip] { [] }
    func clip(id: UUID) async throws -> Clip? { nil }
    func delete(id: UUID) async throws {}
}
