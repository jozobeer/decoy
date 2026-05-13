import AppKit
import AppCommandDispatcher
import Broadcaster
import Dependencies
import DependencyInjection
import Domain
import HotkeyService
import Recorder
import SwiftUI

@main
struct DecoyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Decoy", systemImage: "video.circle") {
            MenuView()
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hides the Dock icon so the binary lives only in the menu bar.
/// SPM executables have no Info.plist to set `LSUIElement`, so the
/// activation policy is flipped programmatically on launch.
///
/// Global hotkey 4 つは起動時に `HotkeyService` へ register し、
/// 終了時に `unregisterAll` で解放する。
/// HotKey ライブラリは Carbon の `RegisterEventHotKey` 経由なので
/// アクセシビリティ権限は不要。
final class AppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.hotkeyService) private var hotkeyService

    private let recorder = Recorder()
    private let broadcaster = Broadcaster()

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
        let bindings = DefaultHotkeyBindings.all(recorder: recorder, dispatcher: dispatcher)
        Task { [hotkeyService] in
            for binding in bindings {
                await hotkeyService.register(binding.shortcut, handler: binding.handler)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Carbon の `RegisterEventHotKey` で確保したスロットは HotKey
        // ライブラリ側で ARC ベースに自動解放されるため、プロセス終了で
        // 十分。明示的 unregister は best-effort で投げて、待たない
        // （terminate コンテキストで runloop を blocking する方が危険）。
        Task { [hotkeyService] in
            await hotkeyService.unregisterAll()
        }
    }
}

/// Placeholder menu content. Real status display lands in #29 (menu bar UI).
private struct MenuView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Decoy")
                .font(.headline)
            Text("MVP scaffold — controls land in #29")
                .font(.caption)
                .foregroundStyle(.secondary)
            Divider()
            Button("Quit Decoy") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding(12)
        .frame(width: 240)
    }
}
