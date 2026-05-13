/// Live-wiring helper. `AVCaptureDeviceAuthorizationProvider` と
/// `AppKitCameraPermissionAlertPresenter` を組み合わせて `AVCameraPermission`
/// actor を構築する。
///
/// Coverage note: この file は AVFoundation / AppKit の live 実装を結線する
/// だけで純粋ロジックを含まないため coverage 対象外
/// （`codecov.yml` の ignore リストに追加済み）。
public extension AVCameraPermission {
    static func live() -> AVCameraPermission {
        AVCameraPermission(
            provider: AVCaptureDeviceAuthorizationProvider(),
            alertPresenter: AppKitCameraPermissionAlertPresenter()
        )
    }
}
