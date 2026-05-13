import AppCommandDispatcher
import AppKit
import Broadcaster
import Dependencies
import DependencyInjection
import Domain
import HotkeyService
import MenuBarUI
import Recorder
import SwiftUI

@main
struct DecoyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Decoy", systemImage: appDelegate.viewModel.isRecording ? "video.circle.fill" : "video.circle") {
            MenuView(viewModel: appDelegate.viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Hides the Dock icon so the binary lives only in the menu bar.
/// SPM executables have no Info.plist to set `LSUIElement`, so the
/// activation policy is flipped programmatically on launch.
///
/// Owns the single Recorder / Broadcaster / dispatcher graph so that
/// global hotkeys と menu bar UI が同じ actor インスタンスへ dispatch
/// する（コマンド経路を一本化）。
///
/// Global hotkey 4 つは起動時に `HotkeyService` へ register し、
/// 終了時に `unregisterAll` で解放する。HotKey ライブラリは Carbon の
/// `RegisterEventHotKey` 経由なのでアクセシビリティ権限は不要。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.hotkeyService) private var hotkeyService

    let recorder = Recorder()
    let broadcaster = Broadcaster()
    lazy var dispatcher = AppCommandDispatcher(recorder: recorder, broadcaster: broadcaster)
    lazy var viewModel = MenuBarViewModel(recorder: recorder, broadcaster: broadcaster, dispatcher: dispatcher)

    nonisolated func applicationWillFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let bindings = DefaultHotkeyBindings.all(recorder: recorder, dispatcher: dispatcher)
        Task { [hotkeyService] in
            for binding in bindings {
                await hotkeyService.register(binding.shortcut, handler: binding.handler)
            }
        }
        Task { [viewModel] in
            await viewModel.start()
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
