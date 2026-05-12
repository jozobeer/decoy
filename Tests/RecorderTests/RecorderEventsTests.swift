import Testing
import Foundation
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
@testable import Recorder

@Suite("RecorderEvents")
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

            let firstStream = await recorder.events
            let secondStream = await recorder.events

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
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
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
            let stream = await recorder.events
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

            let persistentStream = await recorder.events
            let cancelledStream = await recorder.events

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

    /// Collect events emitted while running an action. Subscribes BEFORE the
    /// action so all events are observed. Cancels the collector immediately
    /// after the action returns — by then the actor has processed all queued
    /// commands (e.g. `stopRecording` awaits `consumption?.value`) and any
    /// events have already been broadcast. The caller asserts on the
    /// returned array's count, so a regression that drops an expected event
    /// surfaces as an assertion failure rather than a wall-clock hang.
    fileprivate func collectEvents(
        from recorder: Recorder,
        upTo count: Int,
        while action: @Sendable () async -> Void
    ) async -> [Recorder.Event] {
        let stream = await recorder.events
        let collector = Task<[Recorder.Event], Never> {
            await take(stream, count: max(count, 1))
        }
        await action()
        collector.cancel()
        return await collector.value
    }

    fileprivate func take(_ stream: AsyncStream<Recorder.Event>, count: Int) async -> [Recorder.Event] {
        var collected: [Recorder.Event] = []
        for await event in stream {
            collected.append(event)
            if collected.count >= count { break }
        }
        return collected
    }
}

// MARK: - Test Doubles

private actor FailingClipStore: ClipStore {
    private let saveError: any Error & Sendable

    init(onSave error: any Error & Sendable) {
        self.saveError = error
    }

    func save(_ clip: Clip) async throws {
        throw saveError
    }

    func all() async throws -> [Clip] { [] }
    func clip(id: UUID) async throws -> Clip? { nil }
}

private struct TestError: Error, Equatable, Sendable {
    let label: String
}
