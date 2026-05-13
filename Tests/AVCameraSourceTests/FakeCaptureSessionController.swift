import Foundation
import CoreMedia
import Domain
@testable import AVCameraSource

/// Test double for `CaptureSessionController`. Records lifecycle calls
/// and lets tests push synthetic `Frame`s into the sink that
/// `AVCameraSource` installed.
actor FakeCaptureSessionController: CaptureSessionController {
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var lastPixelFormat: OSType?
    private var sink: (@Sendable (Frame) -> Void)?
    private var onStop: (@Sendable () -> Void)?
    /// When non-nil, the next `start(...)` invocation throws this error
    /// instead of recording the sink. Lets tests exercise the failure
    /// branch in `AVCameraSource.ensureStarted()`.
    var pendingStartError: (any Error)?

    init(pendingStartError: (any Error)? = nil) {
        self.pendingStartError = pendingStartError
    }

    func start(
        pixelFormat: OSType,
        onFrame: @escaping @Sendable (Frame) -> Void,
        onStop: @escaping @Sendable () -> Void
    ) async throws {
        startCount += 1
        lastPixelFormat = pixelFormat
        if let pendingStartError {
            throw pendingStartError
        }
        sink = onFrame
        self.onStop = onStop
    }

    func stop() async {
        stopCount += 1
        onStop?()
        sink = nil
        onStop = nil
    }

    func push(_ frame: Frame) {
        sink?(frame)
    }

    /// Simulate the underlying session ending naturally (e.g., device
    /// disconnect). Triggers the same `onStop` notification a real
    /// session would deliver, then clears the sink.
    func finish() {
        onStop?()
        sink = nil
        onStop = nil
    }
}
