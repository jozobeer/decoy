import Foundation
import OSLog
import CoreMedia
import AVFoundation
import Domain

/// `CameraSource` implementation backed by `AVCaptureSession`.
///
/// Lifecycle:
/// - The underlying `CaptureSessionController` is started on the first
///   `frames()` subscription and stopped after the last subscriber's
///   stream terminates.
/// - Each `frames()` call returns a fresh `AsyncStream<Frame>` — every
///   subscriber sees every frame from its subscription onward. Frames
///   that arrive before any subscriber exists are dropped (the session
///   is not running yet anyway).
///
/// Authorization:
/// - The protocol's `frames()` cannot throw, so permission must be
///   verified before construction via
///   `AVCameraSource.authorized(controller:status:)`. `.denied` /
///   `.restricted` throw `AVCameraSourceError.permissionDenied`;
///   `.authorized` / `.notDetermined` succeed (the caller is expected
///   to drive the authorization prompt elsewhere).
public actor AVCameraSource {
    private let controller: any CaptureSessionController
    private var subscribers: [UUID: AsyncStream<Frame>.Continuation] = [:]
    private var running = false

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "AVCameraSource")
    /// NV12 (`420YpCbCr8BiPlanarVideoRange`) — chosen so the buffer is
    /// compact (1.5 bytes/pixel) and natively supported by the
    /// AVCaptureVideoDataOutput hardware path.
    static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    public init(controller: any CaptureSessionController) {
        self.controller = controller
    }
}

public extension AVCameraSource {
    /// Construct an `AVCameraSource` after verifying authorization.
    ///
    /// `.denied` / `.restricted` throw immediately; `.authorized` and
    /// `.notDetermined` return a usable instance. The caller is
    /// responsible for invoking
    /// `AVCaptureDevice.requestAccess(for:)` when status is
    /// `.notDetermined`.
    static func authorized(
        controller: any CaptureSessionController,
        status: AVAuthorizationStatus
    ) throws -> AVCameraSource {
        switch status {
        case .denied, .restricted:
            throw AVCameraSourceError.permissionDenied
        case .authorized, .notDetermined:
            return AVCameraSource(controller: controller)
        @unknown default:
            throw AVCameraSourceError.permissionDenied
        }
    }

}

extension AVCameraSource: CameraSource {
    public func frames() async -> AsyncStream<Frame> {
        let (stream, continuation) = AsyncStream.makeStream(of: Frame.self)
        let id = UUID()
        subscribers[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeSubscriber(id: id) }
        }
        await ensureStarted()
        return stream
    }
}

extension AVCameraSource {
    /// Start the controller on the first subscriber. Subsequent
    /// subscriptions short-circuit because `running` is already true.
    private func ensureStarted() async {
        guard !running else { return }
        running = true
        do {
            try await controller.start(
                pixelFormat: Self.pixelFormat,
                onFrame: { [weak self] frame in
                    Task { await self?.broadcast(frame) }
                },
                onStop: { [weak self] in
                    Task { await self?.terminate() }
                }
            )
        } catch {
            Self.logger.error("CaptureSessionController.start failed: \(error.localizedDescription, privacy: .private)")
            running = false
            terminate()
        }
    }

    private func broadcast(_ frame: Frame) {
        let snapshot = subscribers
        let terminated = snapshot.compactMap { id, continuation -> UUID? in
            switch continuation.yield(frame) {
            case .terminated: return id
            default: return nil
            }
        }
        terminated.forEach { subscribers.removeValue(forKey: $0) }
    }

    /// Finish every subscriber's stream and reset to the not-running
    /// state. Called when the underlying controller signals stop, or
    /// when start() fails.
    private func terminate() {
        let snapshot = subscribers
        subscribers.removeAll()
        snapshot.values.forEach { $0.finish() }
        running = false
    }

    /// Subscriber cleanup hook fired by `onTermination`. When the
    /// last subscriber drops, stop the underlying controller so we
    /// release the camera.
    private func removeSubscriber(id: UUID) async {
        subscribers.removeValue(forKey: id)
        guard subscribers.isEmpty, running else { return }
        running = false
        await controller.stop()
    }
}
