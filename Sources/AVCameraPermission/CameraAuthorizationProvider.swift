/// カメラ認可ステータスを問い合わせ、未確定なら OS のダイアログを駆動する port。
///
/// `AVCameraPermission` actor の内側 port ― AVFoundation を直接呼ぶのは
/// この protocol の live 実装のみで、orchestrator はこの抽象を介して
/// 状態遷移を扱う。
///
/// 契約：
///
/// - `status` は現在のシステムからの最新のステータスを返す。副作用なし。
/// - `requestAccess()` は `.notDetermined` 状態の初回 1 回だけ意味を持つ。
///   既に決定済みの状態で呼ばれた場合の挙動は OS 依存（既存決定がそのまま返る）。
public protocol CameraAuthorizationProvider: Sendable {
    var status: CameraAuthorizationStatus { get async }
    /// OS の認可ダイアログを表示しユーザーの選択を待つ。true なら許可された。
    func requestAccess() async -> Bool
}
