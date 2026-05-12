import Testing
import Foundation
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
@testable import Recorder

@Suite("RecorderEvents", .timeLimit(.minutes(1)))
struct RecorderEventsTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, data: Data([byte]))
    }

    // MARK: - Save Success → `.saved` 発火

    @Test func startThenStop_withSuccessfulSave_emitsSavedExactlyOnce() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0), Self.frame(0.1)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }

            #expect(events.count == 1)
            try #require(events.first != nil)
            guard case .saved = events[0] else {
                Issue.record("expected .saved, got \(events[0])")
                return
            }
        }
    }

    @Test func savedEvent_carriesClipEqualToStoredClip() async throws {
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02)]
        let source = InMemoryCameraSource(emitting: frames)
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }

            guard case .saved(let observed) = try #require(events.first) else {
                Issue.record("expected .saved, got \(events[0])")
                return
            }
            let stored = try #require(try await store.all().first)
            #expect(observed == stored)
        }
    }

    @Test func twoRecordings_emitSavedTwiceInOrder() async throws {
        let source1 = InMemoryCameraSource(emitting: [Self.frame(0.0, 0x01)])
        let source2 = InMemoryCameraSource(emitting: [Self.frame(0.0, 0x02)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 2) {
                await withDependencies {
                    $0.cameraSource = source1
                } operation: {
                    await recorder.handle(.startRecording)
                    await recorder.handle(.stopRecording)
                }
                await withDependencies {
                    $0.cameraSource = source2
                } operation: {
                    await recorder.handle(.startRecording)
                    await recorder.handle(.stopRecording)
                }
            }

            #expect(events.count == 2)
            for event in events {
                guard case .saved = event else {
                    Issue.record("expected all .saved, got \(event)")
                    return
                }
            }
        }
    }

    // MARK: - Save Failure → `.saveFailed` 発火

    @Test func startThenStop_withFailingStore_emitsSaveFailedExactlyOnce() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = FailingClipStore(onSave: TestError(label: "disk full"))

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }

            #expect(events.count == 1)
            guard case .saveFailed = try #require(events.first) else {
                Issue.record("expected .saveFailed, got \(events[0])")
                return
            }
        }
    }

    @Test func saveFailedEvent_carriesOriginalError() async throws {
        let expected = TestError(label: "quota exceeded")
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = FailingClipStore(onSave: expected)

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }

            guard case .saveFailed(let observed) = try #require(events.first) else {
                Issue.record("expected .saveFailed, got \(events[0])")
                return
            }
            #expect((observed as? TestError) == expected)
        }
    }

    @Test func saveFailure_returnsStateToIdle() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = FailingClipStore(onSave: TestError(label: "boom"))

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            _ = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }
            #expect(await recorder.state == .idle)
        }
    }

    @Test func saveFailure_allowsRecoveryWithNextRecording() async throws {
        let failingStore = FailingClipStore(onSave: TestError(label: "transient"))
        let goodStore = InMemoryClipStore()
        let firstSource = InMemoryCameraSource(emitting: [Self.frame(0.0, 0x01)])
        let secondSource = InMemoryCameraSource(emitting: [Self.frame(0.0, 0x02)])

        try await withDependencies {
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 2) {
                await withDependencies {
                    $0.cameraSource = firstSource
                    $0.clipStore = failingStore
                } operation: {
                    await recorder.handle(.startRecording)
                    await recorder.handle(.stopRecording)
                }
                await withDependencies {
                    $0.cameraSource = secondSource
                    $0.clipStore = goodStore
                } operation: {
                    await recorder.handle(.startRecording)
                    await recorder.handle(.stopRecording)
                }
            }

            try #require(events.count == 2)
            guard case .saveFailed = events[0] else {
                Issue.record("expected first event .saveFailed, got \(events[0])")
                return
            }
            guard case .saved = events[1] else {
                Issue.record("expected second event .saved, got \(events[1])")
                return
            }
        }
    }

    // MARK: - No Save Path → イベント無し

    @Test func emptyRecording_emitsNoEvent() async {
        let source = InMemoryCameraSource(emitting: [])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 0) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }
            #expect(events.isEmpty)
        }
    }

    @Test(arguments: [
        AppCommand.startDecoy(.once),
        AppCommand.startDecoy(.loop),
        AppCommand.startDecoy(.pingPong),
        AppCommand.returnToLive,
    ])
    func foreignCommand_emitsNoEvent(_ foreign: AppCommand) async {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 0) {
                await recorder.handle(foreign)
            }
            #expect(events.isEmpty)
        }
    }

    @Test func stopWhileIdle_emitsNoEvent() async {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 0) {
                await recorder.handle(.stopRecording)
            }
            #expect(events.isEmpty)
        }
    }

    @Test func redundantStart_emitsSavedOnce() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
            }
            #expect(events.count == 1)
        }
    }

    @Test func redundantStop_emitsSavedOnce() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            let events = await collectEvents(from: recorder, upTo: 1) {
                await recorder.handle(.startRecording)
                await recorder.handle(.stopRecording)
                await recorder.handle(.stopRecording)
            }
            #expect(events.count == 1)
        }
    }

    // MARK: - Multi-Subscriber Broadcast

    @Test func twoSubscribersBeforeRecording_bothReceiveSavedEvent() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()

            let firstStream = await recorder.subscribeEvents()
            let secondStream = await recorder.subscribeEvents()

            async let firstEvents: [Recorder.Event] = take(firstStream, count: 1)
            async let secondEvents: [Recorder.Event] = take(secondStream, count: 1)

            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let aResult = await firstEvents
            let bResult = await secondEvents

            #expect(aResult.count == 1)
            #expect(bResult.count == 1)
            guard case .saved = try #require(aResult.first),
                  case .saved = try #require(bResult.first)
            else {
                Issue.record("expected both subscribers to receive .saved")
                return
            }
        }
    }

    @Test func subscriberAfterRecordingStart_stillReceivesSavedEvent() async throws {
        let source = HoldingCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()
            await recorder.handle(.startRecording)

            // subscribe AFTER start but BEFORE stop
            let stream = await recorder.subscribeEvents()
            async let events: [Recorder.Event] = take(stream, count: 1)

            await recorder.handle(.stopRecording)

            let result = await events
            #expect(result.count == 1)
            guard case .saved = try #require(result.first) else {
                Issue.record("expected .saved")
                return
            }
        }
    }

    @Test func subscriberCancellation_doesNotAffectOtherSubscriber() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = Recorder()

            let persistentStream = await recorder.subscribeEvents()
            let cancelledStream = await recorder.subscribeEvents()

            // Persistent subscriber that will observe the event.
            async let persistentEvents: [Recorder.Event] = take(persistentStream, count: 1)

            // Doomed subscriber that gets cancelled before any event flows.
            let doomed = Task<[Recorder.Event], Never> {
                await take(cancelledStream, count: 1)
            }
            doomed.cancel()
            _ = await doomed.value

            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let observed = await persistentEvents
            #expect(observed.count == 1)
            guard case .saved = try #require(observed.first) else {
                Issue.record("expected persistent subscriber to still receive .saved")
                return
            }
        }
    }
}

// MARK: - Test Helpers

extension RecorderEventsTests {

    /// Subscribe and collect events emitted during an action, up to the
    /// drain budget.
    ///
    /// After `action()` returns we cooperatively yield `count + 2` times
    /// (minimum 4) to give the consumer task scheduling slots to drain the
    /// buffered events. Each `for-await` iteration is a single suspension
    /// point, so one yield delivers one event. The `+2` headroom catches
    /// up to two surplus events beyond `count` — enough to break a "emits
    /// exactly N" assertion if the recorder regresses to a duplicate or
    /// off-by-one. If a regression emits more than `count + 2` events the
    /// surplus stays in the buffer and the assertion still passes; this
    /// trade-off is accepted because asserting more than a couple extras
    /// is unusual and unbounded draining would require an extra
    /// synchronisation primitive between actor and consumer.
    private func collectEvents(
        from recorder: Recorder,
        upTo count: Int,
        while action: @Sendable () async -> Void
    ) async -> [Recorder.Event] {
        let stream = await recorder.subscribeEvents()
        let collector = Task<[Recorder.Event], Never> {
            await drain(stream)
        }
        await action()
        let drainCycles = max(count + 2, 4)
        for _ in 0..<drainCycles { await Task.yield() }
        collector.cancel()
        return await collector.value
    }

    private func drain(_ stream: AsyncStream<Recorder.Event>) async -> [Recorder.Event] {
        var collected: [Recorder.Event] = []
        for await event in stream {
            collected.append(event)
        }
        return collected
    }

    private func take(_ stream: AsyncStream<Recorder.Event>, count: Int) async -> [Recorder.Event] {
        var collected: [Recorder.Event] = []
        for await event in stream {
            collected.append(event)
            if collected.count >= count { break }
        }
        return collected
    }
}

// MARK: - Test Doubles

private actor FailingClipStore {
    private let saveError: any Error & Sendable

    init(onSave error: any Error & Sendable) {
        self.saveError = error
    }
}

extension FailingClipStore: ClipStore {
    func save(_ clip: Clip) async throws {
        throw saveError
    }

    func all() async throws -> [Clip] { [] }
    func clip(id: UUID) async throws -> Clip? { nil }
}

private struct TestError: Error, Equatable, Sendable {
    let label: String
}

/// CameraSource test double that emits the preset frames then keeps the
/// stream open until the consumer cancels (via `stopRecording`). Unlike
/// `InMemoryCameraSource`, this source does NOT auto-finish, so tests that
/// need to subscribe AFTER recording starts (but BEFORE `finishRecording`
/// runs) can rely on a deterministic ordering: subscribe → stopRecording
/// → broadcast.
private actor HoldingCameraSource {
    private let preset: [Frame]

    init(emitting frames: [Frame]) {
        self.preset = frames
    }
}

extension HoldingCameraSource: CameraSource {
    func frames() async -> AsyncStream<Frame> {
        let snapshot = preset
        return AsyncStream { continuation in
            snapshot.forEach { continuation.yield($0) }
            // intentionally do not call `continuation.finish()` — wait for
            // consumer cancellation triggered by Recorder.stopRecording.
        }
    }
}
