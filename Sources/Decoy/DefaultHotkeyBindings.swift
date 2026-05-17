import AppCommandDispatcher
import Dependencies
import Domain

/// Issue #30 のアクセプタンス基準で定義された 4 つのデフォルトショートカット。
///
/// - ⌘⇧R: start/stop recording のトグル
/// - ⌘⇧D: startDecoy(.loop)
/// - ⌘⇧L: returnToLive
/// - ⌘⇧O: startDecoy(.once)
///
/// `HotkeyService` は `AppCommand` を知らない設計なので、ハンドラ内で
/// `AppCommandDispatcher.dispatch` を呼んで recorder / broadcaster
/// に fan-out する。トグルは `@Dependency(\.recorder).state` を読んで分岐する。
struct HotkeyBinding: Sendable {
    let shortcut: KeyboardShortcut
    let handler: @Sendable () async -> Void
}

enum DefaultHotkeyBindings {
    static func all(dispatcher: AppCommandDispatcher) -> [HotkeyBinding] {
        [
            toggleRecording(dispatcher: dispatcher),
            startDecoyLoop(dispatcher: dispatcher),
            returnToLive(dispatcher: dispatcher),
            startDecoyOnce(dispatcher: dispatcher),
        ]
    }

    private static func toggleRecording(dispatcher: AppCommandDispatcher) -> HotkeyBinding {
        HotkeyBinding(
            shortcut: KeyboardShortcut(key: .r, modifiers: [.command, .shift])
        ) {
            @Dependency(\.recorder) var recorder
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
