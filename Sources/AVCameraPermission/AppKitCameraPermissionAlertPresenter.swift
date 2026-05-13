import AppKit

/// AppKit (`NSAlert` + `NSWorkspace`) を使った `CameraPermissionAlertPresenter` の live 実装。
///
/// AppKit に直接依存する UI コードのみで構成されており、純粋ロジックは
/// 含まないため coverage 対象外（`codecov.yml` の ignore リストに追加済み）。
///
/// `NSAlert.runModal()` は main thread からの同期呼び出しが前提なので、
/// `presentDeniedAlert()` / `presentRestrictedAlert()` 共に
/// `@MainActor` 隔離で実行する。
public struct AppKitCameraPermissionAlertPresenter: Sendable {
    /// システム設定 > プライバシー > カメラ パネルを直接開く URL。
    /// `URL(string:)` は固定文字列なので nil にはなり得ないが、規約上
    /// force unwrap を許さないため呼び出し側で guard let している。
    static let cameraPrivacyPaneURLString = "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"

    public init() {}
}

extension AppKitCameraPermissionAlertPresenter: CameraPermissionAlertPresenter {
    public func presentDeniedAlert() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "カメラへのアクセスが拒否されています"
            alert.informativeText = "Decoy がカメラを使うには、システム設定 > プライバシーとセキュリティ > カメラ で Decoy を許可してください。"
            alert.addButton(withTitle: "設定を開く")
            alert.addButton(withTitle: "キャンセル")
            let response = alert.runModal()
            guard response == .alertFirstButtonReturn else { return }
            guard let url = URL(string: Self.cameraPrivacyPaneURLString) else { return }
            NSWorkspace.shared.open(url)
        }
    }

    public func presentRestrictedAlert() async {
        await MainActor.run {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "カメラの使用が制限されています"
            alert.informativeText = "MDM 等のポリシーによりカメラ利用が制限されている可能性があります。管理者に問い合わせてください。"
            alert.addButton(withTitle: "OK")
            _ = alert.runModal()
        }
    }
}
