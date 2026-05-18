import AppCommandDispatcher
import AppKit
import Dependencies
import DependencyInjection
import Domain
import HotkeyService
import MenuBarUI
import OSLog
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
/// Owns the dispatcher / view-model graph. Recorder / Broadcaster は
/// `@Dependency(\.recorder)` / `@Dependency(\.broadcaster)` 経由で
/// DI 解決 ― live は `RecorderUseCaseImpl()` / `BroadcasterUseCaseImpl()`
/// の singleton。グローバルホットキーとメニューバー UI は同じ
/// dispatcher を介して同じ actor インスタンスへ dispatch する
/// （コマンド経路を一本化）。
///
/// Global hotkey 4 つは起動時に `HotkeyService` へ register し、
/// 終了時に `unregisterAll` で解放する。HotKey ライブラリは Carbon の
/// `RegisterEventHotKey` 経由なのでアクセシビリティ権限は不要。
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    @Dependency(\.hotkeyService) private var hotkeyService
    @Dependency(\.cameraPermission) private var cameraPermission
    @Dependency(\.cameraExtensionInstaller) private var cameraExtensionInstaller

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "AppDelegate")

    lazy var dispatcher = AppCommandDispatcher()
    lazy var viewModel = MenuBarViewModel(dispatcher: dispatcher)

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // カメラ認可は最優先で取りに行く。CameraSource の live は `static let`
        // (lazy) なので初参照まで評価されず、ここで permission を確保してから
        // viewModel.start() を呼んでも順序は崩れない。失敗時は alert を見せた
        // だけで黙って続行 ― ユーザーが後から設定を変えた場合に viewModel が
        // 再評価できる余地を残す（live cameraSource は失敗時 InMemoryCameraSource
        // に fallback するため crash はしない）。
        Task { [cameraPermission] in
            let result = await cameraPermission.ensureGranted()
            guard case .failure(let error) = result else { return }
            Self.logger.warning("camera permission unavailable: \(String(describing: error), privacy: .public)")
        }
        // CMIO Camera Extension の install は起動毎に試行する。既に installed なら
        // installer 側で早期 return (status .installed 観測時の guard) するため
        // 副作用は最小。status 遷移は logger で観測 ― UI 表示は #44 follow-up で。
        Task { [cameraExtensionInstaller] in
            async let activation: Void = cameraExtensionInstaller.activate()
            for await status in await cameraExtensionInstaller.status {
                Self.logger.info("camera extension install status: \(String(describing: status), privacy: .public)")
                if status == .installed { break }
            }
            _ = await activation
        }
        let bindings = DefaultHotkeyBindings.all(dispatcher: dispatcher)
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
