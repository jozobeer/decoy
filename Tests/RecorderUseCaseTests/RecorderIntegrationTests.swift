import Testing
import Foundation
import Dependencies
import DependencyInjection
import Domain
import InMemoryCameraSource
import InMemoryClipStore
@testable import RecorderUseCase

@Suite("RecorderIntegration")
struct RecorderIntegrationTests {

    // MARK: - Fixtures

    private static let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

    private static func frame(_ pts: TimeInterval, _ byte: UInt8 = 0xAB) -> Frame {
        Frame(presentationTime: pts, pixelData: Data(repeating: byte, count: 64), width: 4, height: 4, pixelFormat: 0x42475241, bytesPerRow: 16)
    }

    private static func uuid(_ hex: String) throws -> UUID {
        try #require(UUID(uuidString: hex))
    }

    // MARK: - Normal Behavior

    @Test func startThenStop_savesClipWithConsumedFrames() async throws {
        let frames = [Self.frame(0.0), Self.frame(0.033), Self.frame(0.066)]
        let source = InMemoryCameraSource(emitting: frames)
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.count == 1)
            #expect(saved.first?.frames == frames)
        }
    }

    @Test func startThenStop_transitionsStateIdleRecordingIdle() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            #expect(await recorder.state == .idle)
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)
            #expect(await recorder.state == .idle)
        }
    }

    // MARK: - Frame Buffering

    @Test func multipleFrames_preservedInOrder() async throws {
        let frames = [Self.frame(0.0, 0x01), Self.frame(0.1, 0x02), Self.frame(0.2, 0x03), Self.frame(0.3, 0x04)]
        let source = InMemoryCameraSource(emitting: frames)
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.first?.frames == frames)
        }
    }

    @Test func singleFrame_savedAsSingleFrameClip() async throws {
        let only = Self.frame(1.5)
        let source = InMemoryCameraSource(emitting: [only])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.first?.frames == [only])
        }
    }

    // MARK: - Clip Metadata

    @Test func clipRecordedAt_reflectsInjectedDateAtStart() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.first?.recordedAt == Self.fixedDate)
        }
    }

    @Test func clipId_equalsInjectedUUID() async throws {
        let firstUUID = try Self.uuid("00000000-0000-0000-0000-000000000000")
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.first?.id == firstUUID)
        }
    }

    @Test func clipDuration_equalsLastPTSMinusFirstPTS() async throws {
        let frames = [Self.frame(0.5), Self.frame(1.0), Self.frame(2.5)]
        let source = InMemoryCameraSource(emitting: frames)
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.first?.duration == 2.0)
        }
    }

    @Test func clipDuration_isZeroForSingleFrame() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(7.5)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.first?.duration == 0)
        }
    }

    // MARK: - Empty Recording

    @Test func emptySource_noClipSaved() async throws {
        let source = InMemoryCameraSource(emitting: [])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.isEmpty)
        }
    }

    @Test func emptySource_stateStillTransitionsCorrectly() async throws {
        let source = InMemoryCameraSource(emitting: [])
        let store = InMemoryClipStore()

        await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)
            #expect(await recorder.state == .idle)
        }
    }

    // MARK: - Idempotency

    @Test func startRecording_whileRecording_isNoOpForBufferAndConsumption() async throws {
        let frames = [Self.frame(0.0), Self.frame(0.1)]
        let source = InMemoryCameraSource(emitting: frames)
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.count == 1)
            // subscribeCount must be 1 — second startRecording must not spawn another stream
            #expect(await source.subscribeCount == 1)
        }
    }

    @Test func stopRecording_whileIdle_doesNotSave() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.isEmpty)
            #expect(await source.subscribeCount == 0)
        }
    }

    @Test func stopRecording_calledTwice_savesOnlyOnce() async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(.startRecording)
            await recorder.handle(.stopRecording)
            await recorder.handle(.stopRecording)

            let saved = try await store.all()
            #expect(saved.count == 1)
        }
    }

    // MARK: - Foreign Commands

    @Test(arguments: [
        AppCommand.startDecoy(.once),
        AppCommand.startDecoy(.loop),
        AppCommand.startDecoy(.pingPong),
        AppCommand.returnToLive,
    ])
    func foreignCommand_doesNotTriggerSaveOrConsumption(_ foreign: AppCommand) async throws {
        let source = InMemoryCameraSource(emitting: [Self.frame(0.0)])
        let store = InMemoryClipStore()

        try await withDependencies {
            $0.cameraSource = source
            $0.clipStore = store
            $0.date = .constant(Self.fixedDate)
            $0.uuid = .incrementing
        } operation: {
            let recorder = RecorderUseCaseImpl()
            await recorder.handle(foreign)

            let saved = try await store.all()
            #expect(saved.isEmpty)
            #expect(await source.subscribeCount == 0)
            #expect(await recorder.state == .idle)
        }
    }
}
