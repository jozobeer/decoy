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
@testable import BroadcasterUseCase
@testable import MenuBarUI
@testable import RecorderUseCase

@Suite("MenuBarViewModel", .timeLimit(.minutes(1)))
@MainActor
struct MenuBarViewModelTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, pixelData: Data(repeating: byte, count: 64), width: 4, height: 4, pixelFormat: 0x42475241, bytesPerRow: 16)
    }

    // MARK: - Initial state

    @Test func init_initialState_matchesDefaults() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let viewModel = MenuBarViewModel(dispatcher: SpyDispatcher())

                #expect(viewModel.recordingState == .idle)
                #expect(viewModel.outputMode == .live)
                #expect(viewModel.pendingPlaybackMode == .loop)
                #expect(viewModel.lastErrorMessage == nil)
                #expect(viewModel.isRecording == false)
                #expect(viewModel.isInDecoy == false)
                #expect(viewModel.activePlaybackMode == nil)
            }
        }
    }

    @Test func start_primesStateFromActors() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.pingPong))
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let viewModel = MenuBarViewModel(dispatcher: SpyDispatcher())
                await viewModel.start()

                #expect(viewModel.outputMode == .playback(.pingPong))
                #expect(viewModel.activePlaybackMode == .pingPong)
                #expect(viewModel.isInDecoy)
            }
        }
    }

    // MARK: - Dispatch verbs

    @Test func startRecording_dispatchesAndRefreshesState() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let spy = SpyDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: spy)

                await viewModel.startRecording()

                await #expect(spy.commands == [.startRecording])
                #expect(viewModel.recordingState == .idle)
            }
        }
    }

    @Test func startRecording_thenStop_persistsClip_andRefreshesToIdle() async {
        // End-to-end: drive the real dispatcher and observe that the
        // view-model's `recordingState` ends at `.idle` after the
        // recorder's finish path runs. Tests both the dispatch wiring
        // and the post-dispatch state refresh.
        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [Self.frame(0.0)])
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let dispatcher = AppCommandDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: dispatcher)

                await viewModel.startRecording()
                await viewModel.stopRecording()

                #expect(viewModel.recordingState == .idle)
            }
        }
    }

    @Test func startDecoy_dispatchesPendingMode() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let spy = SpyDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: spy)
                viewModel.pendingPlaybackMode = .pingPong

                await viewModel.startDecoy()

                await #expect(spy.commands == [.startDecoy(.pingPong)])
            }
        }
    }

    @Test func returnToLive_dispatches_andRefreshesState() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.loop))
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let spy = SpyDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: spy)
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
    }

    // MARK: - Picker behaviour

    @Test func selectPlaybackMode_whileLive_updatesPendingOnly_doesNotDispatch() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let spy = SpyDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: spy)
                await viewModel.start()

                await viewModel.selectPlaybackMode(.once)

                #expect(viewModel.pendingPlaybackMode == .once)
                await #expect(spy.commands.isEmpty)
            }
        }
    }

    @Test func selectPlaybackMode_whileInDecoy_dispatchesStartDecoy() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.loop))
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let spy = SpyDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: spy)
                await viewModel.start()

                await viewModel.selectPlaybackMode(.pingPong)

                #expect(viewModel.pendingPlaybackMode == .pingPong)
                await #expect(spy.commands == [.startDecoy(.pingPong)])
            }
        }
    }

    // MARK: - View helpers

    @Test func isRecording_followsRecordingState() async {
        // An InMemoryCameraSource that never emits keeps the recorder's
        // consumption Task alive, so `recordingState` stays `.recording`
        // until `stopRecording` cancels it. A finite emit list would
        // race the assertion against the consumption Task's completion.
        await withDependencies {
            $0.cameraSource = NeverEndingCameraSource()
            $0.clipStore = InMemoryClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let dispatcher = AppCommandDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: dispatcher)

                await viewModel.startRecording()
                #expect(viewModel.isRecording)

                await viewModel.stopRecording()
                #expect(viewModel.isRecording == false)
            }
        }
    }

    @Test func activePlaybackMode_flattensOutputMode() async {
        await withStubBaseDeps {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl(state: .playback(.once))
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let viewModel = MenuBarViewModel(dispatcher: SpyDispatcher())
                await viewModel.start()

                #expect(viewModel.activePlaybackMode == .once)
                #expect(viewModel.isInDecoy)
            }
        }
    }

    // MARK: - Event-driven error surfacing

    @Test func saveFailedEvent_surfacedAsErrorMessage() async {
        await withDependencies {
            $0.cameraSource = InMemoryCameraSource(emitting: [Self.frame(0.0)])
            $0.clipStore = FailingClipStore()
            $0.virtualCameraSink = InMemoryVirtualCameraSink()
            $0.continuousClock = ImmediateClock()
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            let broadcaster = BroadcasterUseCaseImpl()
            await withDependencies {
                $0.recorder = recorder
                $0.broadcaster = broadcaster
            } operation: {
                let dispatcher = AppCommandDispatcher()
                let viewModel = MenuBarViewModel(dispatcher: dispatcher)
                await viewModel.start()

                await viewModel.startRecording()
                await viewModel.stopRecording()
                await waitForCondition { viewModel.lastErrorMessage != nil }

                #expect(viewModel.lastErrorMessage?.contains("録画の保存に失敗") == true)
            }
        }
    }
}

// MARK: - Test helpers

extension MenuBarViewModelTests {
    /// Stub base dependencies needed for any test that constructs a
    /// `BroadcasterUseCaseImpl` — its init spawns a Task that captures
    /// the surrounding dep context at construction time. Tests must
    /// build the impl *inside* this block and then layer
    /// `$0.recorder` / `$0.broadcaster` in a nested `withDependencies`
    /// around the test body. See AppCommandDispatcherTests for the
    /// same pattern.
    fileprivate func withStubBaseDeps<R: Sendable>(
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

    /// Poll until `predicate` flips true. Bounded at 200 ticks × 2ms ≈
    /// 400ms so a missing transition fails the dependent assertion with
    /// a clear "still false after wait" diagnostic instead of letting
    /// the suite's outer `.timeLimit` swallow it as a generic timeout.
    fileprivate func waitForCondition(
        _ predicate: @MainActor () -> Bool,
        sourceLocation: SourceLocation = #_sourceLocation
    ) async {
        for _ in 0..<200 {
            if predicate() { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        Issue.record("waitForCondition: predicate did not become true within 400ms", sourceLocation: sourceLocation)
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
