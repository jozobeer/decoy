import AVFoundation
import Domain

/// Live-wiring helper. Bridges the DI layer to the OS-resolved default
/// camera + the system authorization status.
///
/// Coverage note: this file consists entirely of AVFoundation device
/// lookup + authorization-status interrogation, both of which require
/// running on a real device. The pure authorization logic is exercised
/// via `AVCameraSource.authorized(controller:status:)` in tests.
public extension AVCameraSource {
    /// Resolve a system camera source for DI wiring.
    ///
    /// Throws `AVCameraSourceError.deviceUnavailable` when no camera is
    /// attached, or `.permissionDenied` when camera access is blocked
    /// by the OS. Successful returns may still need
    /// `AVCaptureDevice.requestAccess(for: .video)` driven separately
    /// when the status is `.notDetermined`.
    static func live() throws -> AVCameraSource {
        guard let controller = AVFoundationCaptureSessionController.usingDefaultDevice() else {
            throw AVCameraSourceError.deviceUnavailable
        }
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        return try authorized(controller: controller, status: status)
    }
}
