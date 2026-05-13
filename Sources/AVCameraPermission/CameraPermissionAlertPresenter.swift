/// ユーザーをシステム設定 > プライバシー > カメラ へ誘導する alert を出す port。
///
/// `AVCameraPermission` actor の内側 port ― AppKit を呼ぶのは
/// この protocol の live 実装のみで、orchestrator は `denied` / `restricted` の
/// 分岐から「alert を出すべき」という意図だけをここに委ねる。
///
/// 契約：
///
/// - `presentDeniedAlert()` はユーザーが過去に拒否したケース向け。
///   「設定を開く」ボタン押下時に実装側で `NSWorkspace.shared.open(...)` を呼ぶ。
/// - `presentRestrictedAlert()` は MDM / ペアレンタルコントロール向け。
///   ユーザー側で解除できない可能性が高いので OK ボタンのみで構わない。
public protocol CameraPermissionAlertPresenter: Sendable {
    func presentDeniedAlert() async
    func presentRestrictedAlert() async
}
