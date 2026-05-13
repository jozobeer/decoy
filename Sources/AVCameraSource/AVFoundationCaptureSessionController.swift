import Foundation
import OSLog
import AVFoundation
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
public final class AVFoundationCaptureSessionController: NSObject, @unchecked Sendable {
    private let device: AVCaptureDevice
    private let session: AVCaptureSession
    private let output: AVCaptureVideoDataOutput
    private let queue: DispatchQueue
    private let frameSink: FrameSink

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "AVFoundationCaptureSessionController")

    public init(device: AVCaptureDevice) {
        self.device = device
        self.session = AVCaptureSession()
        self.output = AVCaptureVideoDataOutput()
        self.queue = DispatchQueue(label: "beer.jozo.decoy.AVFoundationCaptureSessionController")
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
    public func start(
        pixelFormat: OSType,
        onFrame: @escaping @Sendable (Frame) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) async throws {
        frameSink.update(onFrame: onFrame, onStop: onStop)
        let input = try AVCaptureDeviceInput(device: device)
        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            throw AVCameraSourceError.deviceUnavailable
        }
        session.addInput(input)
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: pixelFormat]
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            throw AVCameraSourceError.deviceUnavailable
        }
        session.addOutput(output)
        session.commitConfiguration()
        session.startRunning()
    }

    public func stop() async {
        guard session.isRunning else { return }
        session.stopRunning()
        frameSink.signalStop()
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
