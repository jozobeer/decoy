import Domain
import Foundation
import Testing
@testable import MachPortFrameReceiver

@Suite(.serialized)
struct MachPortFrameReceiverTests {
    @Test
    func start_emitsFrames_fromIncomingMessages() async throws {
        let messages = [
            IncomingFrameMessage(surfacePort: ReceiverMachPortToken(raw: 1), presentationTime: 1, width: 4, height: 4),
            IncomingFrameMessage(surfacePort: ReceiverMachPortToken(raw: 2), presentationTime: 2, width: 4, height: 4),
        ]
        let server = ScriptedServer(messages: messages)
        let materializer = StubMaterializer()
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: materializer
        )
        let frames = await receiver.frames
        try await receiver.start()
        var collected: [Frame] = []
        for await frame in frames {
            collected.append(frame)
            if collected.count == messages.count { break }
        }
        #expect(collected.map(\.presentationTime) == [1, 2])
        await receiver.stop()
    }

    @Test
    func start_concurrent_singleCheckIn() async throws {
        let server = CountingServer()
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        async let a: Void = receiver.start()
        async let b: Void = receiver.start()
        async let c: Void = receiver.start()
        _ = try await (a, b, c)
        let calls = await server.callCount
        #expect(calls == 1)
        await receiver.stop()
    }

    @Test
    func start_checkInFailure_movesToStopped_throws() async throws {
        let server = FailFirstThenSucceedServer(error: MachPortReceiverError.checkInFailed(serviceName: "x", code: -1))
        let receiver = MachPortFrameReceiver(
            serviceName: "x",
            server: server,
            materializer: StubMaterializer()
        )
        do {
            try await receiver.start()
            Issue.record("start() should have thrown")
        } catch let error as MachPortReceiverError {
            #expect(error == .checkInFailed(serviceName: "x", code: -1))
        }
        // 同一 instance で再 start ― 失敗後 state が .stopped に倒れて
        // いれば retry できる契約。
        try await receiver.start()
        let calls = await server.callCount
        #expect(calls == 2)
        await receiver.stop()
    }

    @Test
    func stopDuringStartup_doesNotResurrectListener() async throws {
        let server = SuspendingServer()
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        // start() の前に subscribe する ― stop() が finishAllContinuations
        // を呼ぶことを観測したい。
        let frames = await receiver.frames
        async let startResult: Void = receiver.start()
        await server.waitUntilMessagesCalled()
        // start() は server.messages の await で suspending ― ここで
        // stop() を割り込ませる。actor reentrancy で stop() は state
        // を `.stopped` に倒し finishAllContinuations を呼ぶ。
        await receiver.stop()
        // start() を unblock。本来なら state = .listening に進みかけるが、
        // race fix で `.stopped` を尊重して return するはず ― 再 listener
        // は spawn されない。
        await server.release()
        _ = try await startResult
        var collected = 0
        for await _ in frames {
            collected += 1
        }
        #expect(collected == 0)
    }

    @Test
    func stop_finishesAllSubscriberStreams() async throws {
        let server = ScriptedServer(messages: [])
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        let framesA = await receiver.frames
        let framesB = await receiver.frames
        try await receiver.start()
        await receiver.stop()
        var aCount = 0
        for await _ in framesA { aCount += 1 }
        var bCount = 0
        for await _ in framesB { bCount += 1 }
        // 受け取り中に start→stop ＝ frame は来ないがストリームは finish する
        #expect(aCount == 0)
        #expect(bCount == 0)
    }

    @Test
    func stop_afterIdle_isNoOp() async throws {
        let server = ScriptedServer(messages: [])
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        await receiver.stop()
        // server.stop() は呼ばれない (state が idle のまま) ことを countingServer で別途確認
        let stopServer = CountingServer()
        let receiver2 = MachPortFrameReceiver(
            serviceName: "test.service",
            server: stopServer,
            materializer: StubMaterializer()
        )
        await receiver2.stop()
        let stops = await stopServer.stopCount
        #expect(stops == 0)
    }

    @Test
    func restart_afterStop_isAllowed() async throws {
        let server = ToggleServer()
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        try await receiver.start()
        await receiver.stop()
        try await receiver.start()
        let calls = await server.callCount
        #expect(calls == 2)
        await receiver.stop()
    }

    @Test
    func deliver_materializeFailure_dropsFrame_keepsListening() async throws {
        let messages = [
            IncomingFrameMessage(surfacePort: ReceiverMachPortToken(raw: 1), presentationTime: 1, width: 4, height: 4),
            IncomingFrameMessage(surfacePort: ReceiverMachPortToken(raw: 2), presentationTime: 2, width: 4, height: 4),
            IncomingFrameMessage(surfacePort: ReceiverMachPortToken(raw: 3), presentationTime: 3, width: 4, height: 4),
        ]
        let server = ScriptedServer(messages: messages)
        let materializer = SelectiveMaterializer(failPort: 2)
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: materializer
        )
        let frames = await receiver.frames
        try await receiver.start()
        var collected: [Frame] = []
        for await frame in frames {
            collected.append(frame)
            if collected.count == 2 { break }
        }
        #expect(collected.map(\.presentationTime) == [1, 3])
        await receiver.stop()
    }

    @Test
    func serverStreamEnd_finishesSubscribers() async throws {
        let server = ScriptedServer(messages: [
            IncomingFrameMessage(surfacePort: ReceiverMachPortToken(raw: 1), presentationTime: 1, width: 4, height: 4),
        ])
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        let frames = await receiver.frames
        try await receiver.start()
        var collected: [Frame] = []
        for await frame in frames {
            collected.append(frame)
        }
        #expect(collected.count == 1)
        await receiver.stop()
    }

    @Test
    func serverStreamError_finishesSubscribers() async throws {
        let server = ErroringServer(error: MachPortReceiverError.recvFailed(code: -42))
        let receiver = MachPortFrameReceiver(
            serviceName: "test.service",
            server: server,
            materializer: StubMaterializer()
        )
        let frames = await receiver.frames
        try await receiver.start()
        var collected: [Frame] = []
        for await frame in frames {
            collected.append(frame)
        }
        #expect(collected.isEmpty)
        await receiver.stop()
    }
}

// MARK: - Fakes

private struct ScriptedServer: MachPortServer {
    let messages: [IncomingFrameMessage]

    func messages(serviceName _: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        let payload = messages
        return AsyncThrowingStream { continuation in
            payload.forEach { continuation.yield($0) }
            continuation.finish()
        }
    }

    func stop() async {}
}

private actor CountingServer: MachPortServer {
    var callCount = 0
    var stopCount = 0

    func messages(serviceName _: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        callCount += 1
        try await Task.sleep(nanoseconds: 1_000_000)
        return AsyncThrowingStream { $0.finish() }
    }

    func stop() async {
        stopCount += 1
    }
}

private actor FailFirstThenSucceedServer: MachPortServer {
    let error: Error
    var callCount = 0

    init(error: Error) {
        self.error = error
    }

    func messages(serviceName _: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        callCount += 1
        guard callCount > 1 else { throw error }
        return AsyncThrowingStream { $0.finish() }
    }

    func stop() async {}
}

private actor SuspendingServer: MachPortServer {
    private var entered = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var pendingRelease: CheckedContinuation<Void, Never>?

    func messages(serviceName _: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        markEntered()
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            pendingRelease = continuation
        }
        return AsyncThrowingStream { $0.finish() }
    }

    func stop() async {}

    func waitUntilMessagesCalled() async {
        guard !entered else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            enteredContinuations.append(continuation)
        }
    }

    func release() {
        pendingRelease?.resume()
        pendingRelease = nil
    }

    private func markEntered() {
        entered = true
        let pending = enteredContinuations
        enteredContinuations.removeAll()
        pending.forEach { $0.resume() }
    }
}

private actor ToggleServer: MachPortServer {
    var callCount = 0

    func messages(serviceName _: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        callCount += 1
        return AsyncThrowingStream { $0.finish() }
    }

    func stop() async {}
}

private struct ErroringServer: MachPortServer {
    let error: Error

    func messages(serviceName _: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        let captured = error
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: captured)
        }
    }

    func stop() async {}
}

private struct StubMaterializer: IOSurfaceMaterializer {
    func frame(from message: IncomingFrameMessage) async throws -> Frame {
        Frame(
            presentationTime: message.presentationTime,
            pixelData: Data(),
            width: message.width,
            height: message.height,
            pixelFormat: 0x42475241,
            bytesPerRow: message.width * 4
        )
    }
}

private struct SelectiveMaterializer: IOSurfaceMaterializer {
    let failPort: UInt32

    func frame(from message: IncomingFrameMessage) async throws -> Frame {
        guard message.surfacePort.raw != failPort else {
            throw MachPortReceiverError.surfaceLookupFailed(code: -1)
        }
        return Frame(
            presentationTime: message.presentationTime,
            pixelData: Data(),
            width: message.width,
            height: message.height,
            pixelFormat: 0x42475241,
            bytesPerRow: message.width * 4
        )
    }
}
