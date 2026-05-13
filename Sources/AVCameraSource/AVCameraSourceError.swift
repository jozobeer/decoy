import Foundation

/// Errors surfaced by `AVCameraSource` outside of the `frames()`
/// `AsyncStream`.
///
/// `CameraSource.frames()` returns `AsyncStream<Frame>` which cannot
/// throw. Errors that block stream creation (camera permission denied,
/// no available device) must surface at construction time instead.
public enum AVCameraSourceError: Error, Equatable, Sendable {
    /// Camera access has been denied or restricted by the OS.
    case permissionDenied
    /// No `AVCaptureDevice` is available for the requested media type.
    case deviceUnavailable
}
