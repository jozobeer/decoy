import Foundation
import CoreMedia
import Domain

/// Port that abstracts the underlying AVFoundation capture session.
/// The production implementation
/// (`AVFoundationCaptureSessionController`) owns `AVCaptureSession`,
/// `AVCaptureDeviceInput`, and `AVCaptureVideoDataOutput`; tests inject
/// a fake that simply records lifecycle calls and pushes synthetic
/// `Frame`s into the `onFrame` callback.
///
/// Contract:
/// - `start` is called once before any frames flow. Implementations
///   must configure the underlying pipeline with the requested
///   `pixelFormat` and begin delivering frames via `onFrame`.
/// - `onStop` is invoked when the session terminates for any reason
///   (device disconnect, runtime error, etc.).
/// - `stop` is called when `AVCameraSource` no longer has subscribers
///   and must release the underlying resources. Idempotent.
public protocol CaptureSessionController: Sendable {
    func start(
        pixelFormat: OSType,
        onFrame: @escaping @Sendable (Frame) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) async throws

    func stop() async
}
