import Foundation
import OSLog
@preconcurrency import AVFoundation
import CoreMedia
import Domain

/// Production `CaptureSessionController` backed by an `AVCaptureSession`
/// + `AVCaptureDeviceInput` + `AVCaptureVideoDataOutput`.
///
/// Coverage note: this file is the thin AVFoundation glue layer that
/// cannot be exercised without a real camera. The translation and
/// lifecycle logic lives in `SampleBufferTranslator` and
/// `AVCameraSource` respectively, both of which ARE covered by
/// `AVCameraSourceTests`.
///
/// Threading: `AVCaptureSession.startRunning()` / `stopRunning()` are
/// documented as blocking and should not run on the caller's executor
/// (which may be the main actor). They are dispatched to a private
/// serial `sessionQueue` and `start` / `stop` await their completion.
/// Configuration (`beginConfiguration` / `addInput` / `addOutput`) is
/// documented as thread-safe and runs synchronously on the caller's
/// thread so we don't have to smuggle non-Sendable AVFoundation values
/// across closure boundaries.
public final class AVFoundationCaptureSessionController: NSObject, @unchecked Sendable {
    private let device: AVCaptureDevice
    private let session: AVCaptureSession
    private let output: AVCaptureVideoDataOutput
    private let sampleBufferQueue: DispatchQueue
    private let sessionQueue: DispatchQueue
    private let frameSink: FrameSink

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "AVFoundationCaptureSessionController")

    public init(device: AVCaptureDevice) {
        self.device = device
        self.session = AVCaptureSession()
        self.output = AVCaptureVideoDataOutput()
        self.sampleBufferQueue = DispatchQueue(label: "beer.jozo.decoy.AVFoundationCaptureSessionController.samples")
        self.sessionQueue = DispatchQueue(label: "beer.jozo.decoy.AVFoundationCaptureSessionController.session")
        self.frameSink = FrameSink()
        super.init()
    }

    /// Convenience factory: resolves the system default video device.
    /// Returns `nil` when no camera is attached.
    ///
    /// Side-effecting (queries the OS), hence a function and not a
    /// computed property.
    public static func usingDefaultDevice() -> AVFoundationCaptureSessionController? {
        guard let device = AVCaptureDevice.default(for: .video) else { return nil }
        return AVFoundationCaptureSessionController(device: device)
    }
}

extension AVFoundationCaptureSessionController: CaptureSessionController {
    /// Idempotent across start/stop cycles. Each call:
    ///   1. installs the supplied callbacks,
    ///   2. fully reconfigures the session (any inputs/outputs from a
    ///      prior `start` are removed first so we never accumulate),
    ///   3. starts the session on `sessionQueue` so the caller's
    ///      executor (often the main actor) is not blocked.
    public func start(
        pixelFormat: OSType,
        onFrame: @escaping @Sendable (Frame) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) async throws {
        frameSink.update(onFrame: onFrame, onStop: onStop)
        try configure(pixelFormat: pixelFormat)
        await runOnSessionQueue { [session] in session.startRunning() }
    }

    /// Always tears down — even if the session was never running — so
    /// callbacks and AVFoundation objects are not retained across an
    /// idle period. Idempotent across repeated calls.
    public func stop() async {
        await runOnSessionQueue { [session] in
            if session.isRunning { session.stopRunning() }
        }
        teardownConfiguration()
        frameSink.signalStop()
    }
}

extension AVFoundationCaptureSessionController {
    private func configure(pixelFormat: OSType) throws {
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        // Wipe any leftover wiring from a previous start so repeated
        // start/stop cycles don't accumulate inputs/outputs (or trip
        // `canAddInput`/`canAddOutput`).
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: sampleBufferQueue)
        guard session.canAddInput(input), session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AVCameraSourceError.deviceUnavailable
        }
        session.addInput(input)
        session.addOutput(output)
        session.commitConfiguration()
    }

    private func teardownConfiguration() {
        session.beginConfiguration()
        session.inputs.forEach(session.removeInput)
        session.outputs.forEach(session.removeOutput)
        session.commitConfiguration()
    }

    private func runOnSessionQueue(_ work: @escaping @Sendable () -> Void) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sessionQueue.async {
                work()
                continuation.resume()
            }
        }
    }
}

extension AVFoundationCaptureSessionController: AVCaptureVideoDataOutputSampleBufferDelegate {
    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let f = frame(from: sampleBuffer) else { return }
        frameSink.deliver(f)
    }
}

/// Mutable holder for the `onFrame` / `onStop` closures. Wrapped in a
/// lock because AVFoundation delivers samples on a background queue
/// independent of the actor that owns this controller.
private final class FrameSink: @unchecked Sendable {
    private let lock = NSLock()
    private var onFrame: (@Sendable (Frame) -> Void)?
    private var onStop: (@Sendable () -> Void)?

    func update(
        onFrame: @escaping @Sendable (Frame) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) {
        lock.lock()
        defer { lock.unlock() }
        self.onFrame = onFrame
        self.onStop = onStop
    }

    func deliver(_ frame: Frame) {
        lock.lock()
        let sink = onFrame
        lock.unlock()
        sink?(frame)
    }

    func signalStop() {
        lock.lock()
        let stop = onStop
        onFrame = nil
        onStop = nil
        lock.unlock()
        stop?()
    }
}
