import Dependencies
import Domain
import Foundation
import SwiftUI

/// View-model backing the menu-bar UI. Owns the displayed
/// `RecordingState` / `OutputMode` snapshots and the dispatch verb
/// the View calls into.
///
/// State refresh strategy: `RecordingState` and `OutputMode` are not
/// carried by `RecorderEvent` / `BroadcasterEvent` (those streams
/// surface I/O failures, not transitions). After every dispatch and on
/// every event arrival, the view-model reads the actors' authoritative
/// `state` properties back. This keeps the UI in lockstep with the
/// underlying actors without inventing a parallel state machine.
///
/// Lifetimes: both event tasks iterate passive value facades
/// (`RecorderEvents` / `BroadcasterEvents`) and use `defer { Task {
/// await events.cancel() } }` so the actor-side subscriber slot is
/// released whether the task ends naturally, is cancelled before
/// iteration begins, or is cancelled mid-iteration. On `deinit` we
/// cancel both Tasks; cancellation fires the `defer` cleanup which
/// hops back into the actor to release the slot.
@MainActor
public final class MenuBarViewModel: ObservableObject {
    @Published public private(set) var recordingState: RecordingState = .idle
    @Published public private(set) var outputMode: OutputMode = .live
    /// Decoy-mode selection bound to the playback Picker. Persists across
    /// `.returnToLive` so toggling back into decoy keeps the user's last
    /// pick; defaults to `.loop` because the Dream is to *show* a stable
    /// loop while the operator steps away.
    @Published public var pendingPlaybackMode: PlaybackMode = .loop
    /// Latest user-visible failure surfaced via the event streams.
    /// Cleared by the View after acknowledgement; the View-Model never
    /// auto-clears so brief failures don't get lost in a refresh storm.
    @Published public var lastErrorMessage: String?

    @Dependency(\.recorder) private var recorder
    @Dependency(\.broadcaster) private var broadcaster
    private let dispatcher: any AppCommandDispatching

    private var recorderEventTask: Task<Void, Never>?
    private var broadcasterEventTask: Task<Void, Never>?

    public init(dispatcher: any AppCommandDispatching) {
        self.dispatcher = dispatcher
    }

    deinit {
        recorderEventTask?.cancel()
        broadcasterEventTask?.cancel()
    }
}

// MARK: - Lifecycle

extension MenuBarViewModel {
    /// Wire up event subscriptions and prime the published state with
    /// the actors' current values. Idempotent — calling twice tears the
    /// existing subscriptions down first so we never stack iterators.
    public func start() async {
        recorderEventTask?.cancel()
        broadcasterEventTask?.cancel()
        await refreshState()
        recorderEventTask = makeRecorderEventTask()
        broadcasterEventTask = makeBroadcasterEventTask()
    }
}

// MARK: - Command intents (View-facing)

extension MenuBarViewModel {
    public func startRecording() async {
        await dispatcher.dispatch(.startRecording)
        await refreshState()
    }

    public func stopRecording() async {
        await dispatcher.dispatch(.stopRecording)
        await refreshState()
    }

    /// Enter decoy with the View-Model's currently selected
    /// `pendingPlaybackMode`. Surfaced as a no-arg call so the View can
    /// bind a single "Start decoy" button without re-passing the mode.
    public func startDecoy() async {
        await dispatcher.dispatch(.startDecoy(pendingPlaybackMode))
        await refreshState()
    }

    /// Change the playback mode while staying in decoy. When the
    /// Broadcaster is already on `.playback`, the new mode is dispatched
    /// immediately so the picker behaves like a live switch. When it's
    /// `.live`, only the pending selection updates — the user opts into
    /// decoy explicitly via the Start button.
    public func selectPlaybackMode(_ mode: PlaybackMode) async {
        pendingPlaybackMode = mode
        guard case .playback = outputMode else { return }
        await dispatcher.dispatch(.startDecoy(mode))
        await refreshState()
    }

    public func returnToLive() async {
        await dispatcher.dispatch(.returnToLive)
        await refreshState()
    }
}

// MARK: - State refresh + event loops

extension MenuBarViewModel {
    private func refreshState() async {
        recordingState = await recorder.state
        outputMode = await broadcaster.state
    }

    private func makeRecorderEventTask() -> Task<Void, Never> {
        let recorder = self.recorder
        return Task { [weak self] in
            let events = await recorder.subscribeEvents()
            // Cleanup must run even if this Task is cancelled before
            // `for await` is entered. Otherwise the actor-side subscriber
            // slot leaks across `start()`'s cancel→recreate cycle.
            defer { Task { await events.cancel() } }
            for await event in events {
                await self?.handleRecorderEvent(event)
            }
        }
    }

    private func makeBroadcasterEventTask() -> Task<Void, Never> {
        let broadcaster = self.broadcaster
        return Task { [weak self] in
            let events = await broadcaster.subscribeEvents()
            // Symmetric cleanup with the recorder task — see comment
            // there for the cancel→recreate leak rationale.
            defer { Task { await events.cancel() } }
            for await event in events {
                await self?.handleBroadcasterEvent(event)
            }
        }
    }

    private func handleRecorderEvent(_ event: RecorderEvent) async {
        switch event {
        case .saved:
            await refreshState()
        case .saveFailed(let error):
            lastErrorMessage = "録画の保存に失敗しました: \(error.localizedDescription)"
            await refreshState()
        }
    }

    private func handleBroadcasterEvent(_ event: BroadcasterEvent) async {
        switch event {
        case .sendFailed(let error):
            lastErrorMessage = "出力に失敗しました: \(error.localizedDescription)"
        case .storeReadFailed(let error):
            lastErrorMessage = "クリップの読み込みに失敗しました: \(error.localizedDescription)"
        }
        await refreshState()
    }
}

// MARK: - View helpers

extension MenuBarViewModel {
    /// Flattens `OutputMode.playback(mode)` into a Picker-friendly
    /// optional. `nil` means the Broadcaster is on `.live` and the
    /// playback Picker should reflect the pending selection only.
    public var activePlaybackMode: PlaybackMode? {
        guard case .playback(let mode) = outputMode else { return nil }
        return mode
    }

    public var isRecording: Bool { recordingState == .recording }
    public var isInDecoy: Bool { activePlaybackMode != nil }
}
