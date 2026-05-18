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
    /// Single-consumer pipe between the controller's frame callback and
    /// the actor's `broadcast(_:)`. Using one ordered `AsyncStream`
    /// instead of a `Task { … }` per frame guarantees frames reach
    /// subscribers in the order the controller emitted them — without
    /// it, concurrent unstructured Tasks racing into the actor reorder
    /// frames whenever the producer outpaces actor scheduling.
    private var inboundContinuation: AsyncStream<Frame>.Continuation?
    private var consumer: Task<Void, Never>?
    /// Set true when entering `.stopping` due to an unexpected controller
    /// stop (device disconnect, runtime error). The consumer-completion
    /// hook then terminates subscribers as part of cleanup. For planned
    /// stops triggered by `removeSubscriber` we leave this `false` so
    /// late-arriving subscribers can drive a restart.
    private var terminateOnDrain = false

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
    /// BGRA 8-bit (`kCVPixelFormatType_32BGRA`) — single-plane format
    /// aligned with `DecoyCameraExtension`'s stream descriptor. Going
    /// BGRA end-to-end (camera → ClipStore → CMIO sink) lets
    /// `SampleBufferTranslator` copy a single contiguous byte run into
    /// `Frame.pixelData` and lets the IPC boundary re-materialise the
    /// `IOSurface` without plane gymnastics, at the cost of ~2.66×
    /// memory vs NV12 (still trivial for desktop 720p/1080p streams).
    static let pixelFormat: OSType = kCVPixelFormatType_32BGRA

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
        // Bounded inbound buffer mirrors `perSubscriberBufferDepth`: under
        // momentary consumer lag we tolerate a short queue and beyond
        // that drop the oldest frame so memory stays flat. Unbounded
        // would let AVFoundation's producer outpace our actor hop and
        // grow without limit.
        let (inbound, continuation) = AsyncStream.makeStream(
            of: Frame.self,
            bufferingPolicy: .bufferingNewest(Self.perSubscriberBufferDepth)
        )
        inboundContinuation = continuation
        consumer = Task { [weak self] in
            for await frame in inbound {
                await self?.broadcast(frame)
            }
            await self?.consumerFinished()
        }
        do {
            try await controller.start(
                pixelFormat: Self.pixelFormat,
                onFrame: { frame in
                    continuation.yield(frame)
                },
                onStop: { [weak self] in
                    Task { await self?.handleControllerStopped() }
                }
            )
        } catch {
            Self.logger.error("CaptureSessionController.start failed: \(error.localizedDescription, privacy: .private)")
            // Pre-stage the drain transition BEFORE awaiting `stop()`.
            // `controller.stop()` may invoke its `onStop` callback while
            // we are suspended here, scheduling `handleControllerStopped`
            // — without `lifecycle = .stopping` in place, the racing
            // handler's `guard lifecycle == .running` would re-enter the
            // drain and `consumerFinished` could land before this catch
            // body resumes, leaving the actor wedged in `.stopping` with
            // `consumer == nil`. Staging the transition first makes the
            // racing handler short-circuit.
            lifecycle = .stopping
            terminateOnDrain = true
            inboundContinuation?.finish()
            inboundContinuation = nil
            await controller.stop()
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

    /// `onStop` from the controller fires when the underlying session
    /// ends unexpectedly (device disconnect, runtime error). Planned
    /// stops triggered by `removeSubscriber` already set `.stopping`
    /// and finish the inbound pipe themselves, so this guard short-
    /// circuits in that case.
    private func handleControllerStopped() {
        guard lifecycle == .running else { return }
        lifecycle = .stopping
        terminateOnDrain = true
        inboundContinuation?.finish()
        inboundContinuation = nil
    }

    /// Invoked from the consumer Task once it has drained every frame
    /// that was yielded before `inboundContinuation.finish()`. This is
    /// the single point that completes a stop transition — subscribers
    /// terminate (on unexpected stops) and `lifecycle` returns to
    /// `.idle` here, so frames in flight at stop time are guaranteed
    /// to reach subscribers before their streams end.
    private func consumerFinished() {
        consumer = nil
        guard lifecycle == .stopping else { return }
        if terminateOnDrain {
            terminateOnDrain = false
            terminateAllSubscribers()
        }
        lifecycle = .idle
        guard !subscribers.isEmpty else { return }
        Task { [weak self] in await self?.ensureStarted() }
    }

    private func terminateAllSubscribers() {
        let snapshot = subscribers
        subscribers.removeAll()
        snapshot.values.forEach { $0.finish() }
    }

    /// Subscriber cleanup hook fired by `onTermination`. When the last
    /// subscriber drops, stop the underlying controller so we release
    /// the camera. New subscribers that arrive during the stop are
    /// tolerated: `consumerFinished` re-checks the registry and
    /// restarts if any are waiting.
    private func removeSubscriber(id: UUID) async {
        subscribers.removeValue(forKey: id)
        guard subscribers.isEmpty, lifecycle == .running else { return }
        lifecycle = .stopping
        terminateOnDrain = false
        await controller.stop()
        inboundContinuation?.finish()
        inboundContinuation = nil
    }
}
