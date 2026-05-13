/// `AVCaptureDevice.authorizationStatus(for:)` の戻り値を AVFoundation 非依存で
/// 表現する Adapter 層のステータス enum。
///
/// `AVAuthorizationStatus` をそのまま使うと `AVFoundation` import が
/// orchestrator にも伝播してしまい、ピュアな分岐ロジックのテストが
/// AVFoundation 抜きで書けなくなる。ここで一段抽象化することで
/// `AVCameraPermission` actor をフレームワーク非依存にする。
public enum CameraAuthorizationStatus: Equatable, Sendable {
    /// ユーザーが明示的に拒否した。
    case denied
    /// MDM / ペアレンタルコントロール等で利用そのものが許されていない。
    case restricted
    /// 既に許可済み。
    case authorized
    /// まだ尋ねていない（`requestAccess` で初回ダイアログを出せる）。
    case notDetermined
}
