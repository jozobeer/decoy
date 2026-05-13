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
    /// instead of recording the sink. Cleared after one throw so the
    /// subsequent `start` proceeds normally — this matches the
    /// real-world failure mode `AVCameraSource.ensureStarted` is
    /// hardened against (a single transient device error on first start
    /// followed by recovery on the next attempt).
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
            self.pendingStartError = nil
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

    /// Poll-wait until `startCount` reaches `expected`. Used by tests
    /// in place of fixed `Task.sleep` waits — the await gives the
    /// `AVCameraSource` actor's `frames()` continuation room to hop in
    /// and call `start`, then we observe the counter on the next tick.
    /// Bounded at 200 ticks × 2ms = 400ms so a missing transition fails
    /// as a wrong-count assertion downstream instead of hanging.
    func awaitStartCount(_ expected: Int) async {
        for _ in 0..<200 {
            if startCount >= expected { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }

    /// Poll-wait until `stopCount` reaches `expected`. See
    /// `awaitStartCount(_:)` for rationale.
    func awaitStopCount(_ expected: Int) async {
        for _ in 0..<200 {
            if stopCount >= expected { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
    }
}
