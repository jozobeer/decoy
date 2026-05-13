import AppKit
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
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

/// Placeholder menu content. Real status display and command
/// dispatch land in #29 (menu bar UI) and #28 (AppCommandDispatcher).
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
