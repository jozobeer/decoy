import AVFoundation

/// `AVCaptureDevice` を直接呼ぶ `CameraAuthorizationProvider` の live 実装。
///
/// AVFoundation の OS lookup + 認可リクエストでのみ構成されており、
/// 純粋ロジックは含まないため coverage 対象外
/// （`codecov.yml` の ignore リストに追加済み）。
///
/// `requestAccess(for:)` は OS 内部で直列化されるため、複数回呼んでも
/// プロセス毎に決定済み結果がそのまま返る。
public struct AVCaptureDeviceAuthorizationProvider: Sendable {
    public init() {}
}

extension AVCaptureDeviceAuthorizationProvider: CameraAuthorizationProvider {
    public var status: CameraAuthorizationStatus {
        Self.translate(AVCaptureDevice.authorizationStatus(for: .video))
    }

    public func requestAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// `AVAuthorizationStatus` から AVFoundation 非依存の Domain 寄り enum へ変換。
    /// `@unknown default` は将来追加されうる case を `.denied` に倒す ―
    /// 認可されていない以上、デフォルトで「使えない」扱いにする方が安全。
    private static func translate(_ status: AVAuthorizationStatus) -> CameraAuthorizationStatus {
        switch status {
        case .authorized: return .authorized
        case .denied: return .denied
        case .restricted: return .restricted
        case .notDetermined: return .notDetermined
        @unknown default: return .denied
        }
    }
}
