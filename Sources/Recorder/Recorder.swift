import Foundation
import OSLog
import Dependencies
import DependencyInjection
import Domain

public actor Recorder {
    @Dependency(\.cameraSource) private var cameraSource
    @Dependency(\.clipStore) private var clipStore
    @Dependency(\.date) private var date
    @Dependency(\.uuid) private var uuid

    public private(set) var state: RecordingState = .idle
    private var consumption: Task<Void, Never>?
    private var buffer: [Frame] = []
    private var recordedAt: Date?

    private static let logger = Logger(subsystem: "beer.jozo.decoy", category: "Recorder")

    public init() {}

    public func handle(_ command: AppCommand) async {
        switch command {
        case .startRecording:
            await beginRecording()
        case .stopRecording:
            await endRecording()
        case .startDecoy, .returnToLive:
            break
        }
    }
}

extension Recorder {
    private func beginRecording() async {
        guard state == .idle else { return }
        state = .recording
        recordedAt = date.now
        buffer = []
        let source = cameraSource
        consumption = Task { [weak self] in
            let stream = await source.frames()
            for await frame in stream {
                await self?.append(frame)
            }
            await self?.finishRecording()
        }
    }

    private func endRecording() async {
        guard state == .recording else { return }
        consumption?.cancel()
        await consumption?.value
    }

    private func append(_ frame: Frame) {
        buffer.append(frame)
    }

    private func finishRecording() async {
        defer {
            state = .idle
            consumption = nil
            buffer = []
            recordedAt = nil
        }
        guard let first = buffer.first, let last = buffer.last, let recordedAt = recordedAt else { return }
        let clip = Clip(
            id: uuid(),
            recordedAt: recordedAt,
            frames: buffer,
            duration: last.presentationTime - first.presentationTime
        )
        do {
            try await clipStore.save(clip)
        } catch {
            // TODO(#14): surface save failures via Event stream — logging is a stopgap
            Self.logger.error("ClipStore.save failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
