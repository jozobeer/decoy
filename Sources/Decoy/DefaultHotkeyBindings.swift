import AppCommandDispatcher
import Domain
import Recorder

/// Issue #30 のアクセプタンス基準で定義された 4 つのデフォルトショートカット。
///
/// - ⌘⇧R: start/stop recording のトグル
/// - ⌘⇧D: startDecoy(.loop)
/// - ⌘⇧L: returnToLive
/// - ⌘⇧O: startDecoy(.once)
///
/// `HotkeyService` は `AppCommand` を知らない設計なので、ハンドラ内で
/// `AppCommandDispatcher.dispatch` を呼んで `Recorder` / `Broadcaster`
/// に fan-out する。トグルは `Recorder.state` を読んで分岐する。
struct HotkeyBinding: Sendable {
    let shortcut: KeyboardShortcut
    let handler: @Sendable () async -> Void
}

enum DefaultHotkeyBindings {
    static func all(recorder: Recorder, dispatcher: AppCommandDispatcher) -> [HotkeyBinding] {
        [
            toggleRecording(recorder: recorder, dispatcher: dispatcher),
            startDecoyLoop(dispatcher: dispatcher),
            returnToLive(dispatcher: dispatcher),
            startDecoyOnce(dispatcher: dispatcher),
        ]
    }

    private static func toggleRecording(
        recorder: Recorder,
        dispatcher: AppCommandDispatcher
    ) -> HotkeyBinding {
        HotkeyBinding(
            shortcut: KeyboardShortcut(key: .r, modifiers: [.command, .shift])
        ) {
            let state = await recorder.state
            let command: AppCommand = state == .recording ? .stopRecording : .startRecording
            await dispatcher.dispatch(command)
        }
    }

    private static func startDecoyLoop(dispatcher: AppCommandDispatcher) -> HotkeyBinding {
        HotkeyBinding(
            shortcut: KeyboardShortcut(key: .d, modifiers: [.command, .shift])
        ) {
            await dispatcher.dispatch(.startDecoy(.loop))
        }
    }

    private static func returnToLive(dispatcher: AppCommandDispatcher) -> HotkeyBinding {
        HotkeyBinding(
            shortcut: KeyboardShortcut(key: .l, modifiers: [.command, .shift])
        ) {
            await dispatcher.dispatch(.returnToLive)
        }
    }

    private static func startDecoyOnce(dispatcher: AppCommandDispatcher) -> HotkeyBinding {
        HotkeyBinding(
            shortcut: KeyboardShortcut(key: .o, modifiers: [.command, .shift])
        ) {
            await dispatcher.dispatch(.startDecoy(.once))
        }
    }
}
