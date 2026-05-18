import Testing
import Foundation
import CoreVideo
import Domain
@testable import AVCameraSource

@Suite("AVCameraSource")
struct AVCameraSourceTests {
    private static func unitFrame(t: TimeInterval, payload: UInt8) -> Frame {
        Frame(
            presentationTime: t,
            pixelData: Data(repeating: payload, count: 64),
            width: 4, height: 4,
            pixelFormat: 0x42475241, // 'BGRA'
            bytesPerRow: 16
        )
    }

    // MARK: - frames() basic contract

    @Test("frames() returns an AsyncStream that yields frames pushed by the controller")
    func framesYieldsControllerPushedFrames() async throws {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)
        let f1 = Self.unitFrame(t: 0.0, payload: 0x01)
        let f2 = Self.unitFrame(t: 0.033, payload: 0x02)

        let stream = await source.frames()
        // Same scheduling race as `framesArePreservedInOrder`: wait
        // for the sink install hop before pushing.
        await controller.awaitStartCount(1)
        await controller.push(f1)
        await controller.push(f2)
        await controller.finish()

        let collected = await stream.reduce(into: [Frame]()) { $0.append($1) }
        #expect(collected == [f1, f2])
    }

    @Test("frames() starts the controller on first subscriber")
    func framesStartsController() async {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)

        _ = await source.frames()
        // give the actor a tick so the start hop completes
        await Task.yield()
        let started = await controller.startCount
        #expect(started == 1)
    }

    @Test("dropping the last subscriber stops the controller")
    func droppingLastSubscriberStopsController() async {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)

        // iterate the stream from a Task, then cancel the Task —
        // AsyncStream.onTermination fires, the actor cleans up the
        // subscriber slot, and (because that was the last one) tells
        // the controller to stop.
        let task = Task {
            let stream = await source.frames()
            for await _ in stream {}
        }
        // wait for the subscribe + start hop to land deterministically
        await controller.awaitStartCount(1)
        task.cancel()
        _ = await task.value
        // wait for onTermination → removeSubscriber → controller.stop()
        await controller.awaitStopCount(1)
        let stopped = await controller.stopCount
        #expect(stopped == 1)
    }

    @Test("multiple concurrent subscribers each receive frames")
    func multipleSubscribersReceiveFrames() async throws {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)
        let f = Self.unitFrame(t: 1.0, payload: 0xAB)

        let s1 = await source.frames()
        let s2 = await source.frames()
        // Wait for the single shared sink install before pushing
        // (controller starts only once across both subscribers).
        await controller.awaitStartCount(1)
        await controller.push(f)
        await controller.finish()

        async let c1 = s1.reduce(into: [Frame]()) { $0.append($1) }
        async let c2 = s2.reduce(into: [Frame]()) { $0.append($1) }
        let (collected1, collected2) = await (c1, c2)
        #expect(collected1 == [f])
        #expect(collected2 == [f])
    }

    @Test("controller is started only once across multiple subscribers")
    func controllerStartsOnceForMultipleSubscribers() async {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)

        _ = await source.frames()
        _ = await source.frames()
        await Task.yield()
        let started = await controller.startCount
        #expect(started == 1)
    }

    @Test("controller stops only after the last subscriber finishes")
    func controllerStopsAfterLastSubscriberFinishes() async {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)

        let task1 = Task {
            let stream = await source.frames()
            for await _ in stream {}
        }
        let task2 = Task {
            let stream = await source.frames()
            for await _ in stream {}
        }
        // both subscriptions landed → controller started (only once)
        await controller.awaitStartCount(1)

        // cancel only the first subscriber — controller must still be
        // alive because the second subscriber is still iterating
        task1.cancel()
        _ = await task1.value
        // Yield enough times that any (erroneous) stop call would land;
        // since no stop is expected, awaitStopCount falls through after
        // its bounded poll window without setting the counter.
        await controller.awaitStopCount(1)
        let stoppedAfterFirst = await controller.stopCount
        #expect(stoppedAfterFirst == 0)

        // cancel the second — now the controller should stop
        task2.cancel()
        _ = await task2.value
        await controller.awaitStopCount(1)
        let stoppedAfterSecond = await controller.stopCount
        #expect(stoppedAfterSecond == 1)
    }

    // MARK: - frame ordering

    @Test("frames are delivered in the order they are pushed")
    func framesArePreservedInOrder() async throws {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)
        let frames = (0..<5).map { i in
            Self.unitFrame(t: Double(i) * 0.033, payload: UInt8(i))
        }

        let stream = await source.frames()
        // Wait until the source's `frames()` hop has installed the sink
        // on the controller. Without this, `push` may run before the
        // sink is wired and silently drop frames — flaky in serial
        // mode where the scheduler doesn't interleave the start hop.
        await controller.awaitStartCount(1)
        for frame in frames {
            await controller.push(frame)
        }
        await controller.finish()
        let collected = await stream.reduce(into: [Frame]()) { $0.append($1) }
        #expect(collected == frames)
    }

    // MARK: - permission denied

    @Test("when authorization status is denied, init throws permissionDenied")
    func deniedAuthorizationThrowsAtInit() {
        let controller = FakeCaptureSessionController()
        #expect(throws: AVCameraSourceError.permissionDenied) {
            _ = try AVCameraSource.authorized(controller: controller, status: .denied)
        }
    }

    @Test("when authorization status is restricted, init throws permissionDenied")
    func restrictedAuthorizationThrowsAtInit() {
        let controller = FakeCaptureSessionController()
        #expect(throws: AVCameraSourceError.permissionDenied) {
            _ = try AVCameraSource.authorized(controller: controller, status: .restricted)
        }
    }

    @Test("when authorization status is authorized, init returns a usable instance")
    func authorizedStatusReturnsSource() async throws {
        let controller = FakeCaptureSessionController()
        let source = try AVCameraSource.authorized(controller: controller, status: .authorized)
        _ = await source.frames()
        await Task.yield()
        let started = await controller.startCount
        #expect(started == 1)
    }

    @Test("when authorization status is notDetermined, init returns a usable instance (caller drives the prompt)")
    func notDeterminedStatusReturnsSource() async throws {
        let controller = FakeCaptureSessionController()
        let source = try AVCameraSource.authorized(controller: controller, status: .notDetermined)
        _ = await source.frames()
        await Task.yield()
        let started = await controller.startCount
        #expect(started == 1)
    }

    // MARK: - controller start failure

    @Test("when the controller fails to start, the stream finishes immediately")
    func controllerStartFailureTerminatesStream() async {
        struct StartFailure: Error {}
        let controller = FakeCaptureSessionController(pendingStartError: StartFailure())
        let source = AVCameraSource(controller: controller)

        let stream = await source.frames()
        let collected = await stream.reduce(into: [Frame]()) { $0.append($1) }
        #expect(collected.isEmpty)
    }

    // MARK: - configuration contract

    @Test("controller is configured for the requested pixel format on start")
    func controllerReceivesPixelFormatOnStart() async {
        let controller = FakeCaptureSessionController()
        let source = AVCameraSource(controller: controller)

        _ = await source.frames()
        await Task.yield()
        let pixelFormat = await controller.lastPixelFormat
        #expect(pixelFormat == kCVPixelFormatType_32BGRA)
    }
}
