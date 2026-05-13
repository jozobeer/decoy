import Domain

/// `CameraPermission` の orchestrator 実装。
///
/// AVFoundation / AppKit には直接依存せず、内側 port
/// (`CameraAuthorizationProvider`, `CameraPermissionAlertPresenter`)
/// 経由で動く。Live 配線は `AVCameraPermission+Live.swift` の `live()` で
/// AVFoundation / AppKit 実装を注入する。
///
/// 状態遷移：
///
/// | status         | 動作                                         | 結果              |
/// |----------------|---------------------------------------------|-------------------|
/// | `authorized`    | no-op                                       | `.success`        |
/// | `notDetermined` | `provider.requestAccess()` でダイアログ表示 | grant→success / deny→failure(.denied) |
/// | `denied`        | `presenter.presentDeniedAlert()`            | `.failure(.denied)` |
/// | `restricted`    | `presenter.presentRestrictedAlert()`        | `.failure(.restricted)` |
///
/// `denied`/`restricted` で `requestAccess` を呼ばないのは意図的：OS は決定済み
/// 状態で `requestAccess` を呼んでも no-op で false を返すだけで、ユーザーから
/// 見るとダイアログが出ないまま勝手に拒否扱いになる挙動を引き起こす。
/// 代わりに alert で「設定 > プライバシー」へ誘導する。
public actor AVCameraPermission {
    private let provider: any CameraAuthorizationProvider
    private let alertPresenter: any CameraPermissionAlertPresenter

    public init(
        provider: any CameraAuthorizationProvider,
        alertPresenter: any CameraPermissionAlertPresenter
    ) {
        self.provider = provider
        self.alertPresenter = alertPresenter
    }
}

extension AVCameraPermission: CameraPermission {
    public func ensureGranted() async -> Result<Void, CameraPermissionError> {
        switch await provider.status {
        case .authorized:
            return .success(())
        case .notDetermined:
            let granted = await provider.requestAccess()
            return granted ? .success(()) : .failure(.denied)
        case .denied:
            await alertPresenter.presentDeniedAlert()
            return .failure(.denied)
        case .restricted:
            await alertPresenter.presentRestrictedAlert()
            return .failure(.restricted)
        }
    }
}
