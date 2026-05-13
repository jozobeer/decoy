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
/// - Lifecycle is tracked by an explicit three-state machine
///   (`.idle` / `.running` / `.stopping`) so a new subscription cannot
///   race with an in-flight `controller.stop()`. While stopping, new
///   subscribers register their continuation but do not trigger a
///   restart; once the stop completes, the cleanup hook checks for
///   late arrivals and restarts the controller if any are waiting.
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
    private var lifecycle: LifecycleState = .idle

    /// Bounded buffer per subscriber. Cameras run at ~30–60 fps; under
    /// momentary consumer lag we tolerate a short queue (~quarter
    /// second at 30 fps) and beyond that drop the oldest frames so
    /// memory does not grow unboundedly. The alternative — pausing the
    /// producer — would back-pressure AVFoundation, which is not what
    /// callers want for a live feed. Dropped frames are silent at this
    /// layer; consumers that need rate stats should observe their own
    /// timestamps.
    static let perSubscriberBufferDepth = 8

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "AVCameraSource")
    /// NV12 (`420YpCbCr8BiPlanarVideoRange`) — chosen so the buffer is
    /// compact (1.5 bytes/pixel) and natively supported by the
    /// AVCaptureVideoDataOutput hardware path.
    static let pixelFormat: OSType = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange

    public init(controller: any CaptureSessionController) {
        self.controller = controller
    }

    enum LifecycleState {
        case idle, running, stopping
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
        let (stream, continuation) = AsyncStream.makeStream(
            of: Frame.self,
            bufferingPolicy: .bufferingNewest(Self.perSubscriberBufferDepth)
        )
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
    /// subscriptions short-circuit because `lifecycle` is already
    /// `.running`. Calls during `.stopping` short-circuit too — the
    /// subscriber's continuation is registered, and the stop completion
    /// path picks it up and restarts.
    private func ensureStarted() async {
        guard lifecycle == .idle else { return }
        lifecycle = .running
        do {
            try await controller.start(
                pixelFormat: Self.pixelFormat,
                onFrame: { [weak self] frame in
                    Task { await self?.broadcast(frame) }
                },
                onStop: { [weak self] in
                    Task { await self?.handleControllerStopped() }
                }
            )
        } catch {
            Self.logger.error("CaptureSessionController.start failed: \(error.localizedDescription, privacy: .private)")
            // Roll back any partial controller state before tearing down
            // subscribers; AVFoundation may have set up resources before
            // throwing and leaving them attached can poison the next
            // start attempt.
            await controller.stop()
            lifecycle = .idle
            terminateAllSubscribers()
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

    /// `onStop` from the controller fires only on unexpected end (device
    /// disconnect, runtime error). Expected stops triggered by
    /// `removeSubscriber` set `lifecycle = .stopping` first and consume
    /// the signal silently — we don't want them to terminate subscribers
    /// that arrived during the stop window.
    private func handleControllerStopped() {
        guard lifecycle == .running else { return }
        terminateAllSubscribers()
        lifecycle = .idle
    }

    private func terminateAllSubscribers() {
        let snapshot = subscribers
        subscribers.removeAll()
        snapshot.values.forEach { $0.finish() }
    }

    /// Subscriber cleanup hook fired by `onTermination`. When the last
    /// subscriber drops, stop the underlying controller so we release
    /// the camera. New subscribers that arrive during the stop are
    /// tolerated: after `controller.stop()` returns we re-check and
    /// restart if any are waiting.
    private func removeSubscriber(id: UUID) async {
        subscribers.removeValue(forKey: id)
        guard subscribers.isEmpty, lifecycle == .running else { return }
        lifecycle = .stopping
        await controller.stop()
        lifecycle = .idle
        guard !subscribers.isEmpty else { return }
        await ensureStarted()
    }
}
