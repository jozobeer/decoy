import Dependencies
import DependencyInjection
import Domain

public actor Broadcaster {
    private nonisolated let cameraSource: any CameraSource
    private nonisolated let virtualCameraSink: any VirtualCameraSink

    public private(set) var state: OutputMode
    private var routing: Task<Void, Never>?

    public init(state: OutputMode = .live) {
        @Dependency(\.cameraSource) var cameraSource
        @Dependency(\.virtualCameraSink) var virtualCameraSink
        self.cameraSource = cameraSource
        self.virtualCameraSink = virtualCameraSink
        self.state = state
        if state == .live {
            self.routing = Self.makeRoutingTask(source: cameraSource, sink: virtualCameraSink)
        }
    }

    public func handle(_ command: AppCommand) async {
        switch command {
        case .startDecoy(let mode):
            let wasLive = state == .live
            state = .playback(mode)
            if wasLive {
                await stopRouting()
            }
        case .returnToLive:
            guard state != .live else { return }
            state = .live
            startRouting()
        case .startRecording, .stopRecording:
            break
        }
    }

    public func shutdown() async throws {
        await stopRouting()
    }
}

extension Broadcaster {
    private func startRouting() {
        guard routing == nil else { return }
        routing = Self.makeRoutingTask(source: cameraSource, sink: virtualCameraSink)
    }

    private func stopRouting() async {
        let task = routing
        routing = nil
        task?.cancel()
        await task?.value
    }

    private static func makeRoutingTask(
        source: any CameraSource,
        sink: any VirtualCameraSink
    ) -> Task<Void, Never> {
        Task {
            let stream = await source.frames()
            for await frame in stream {
                if Task.isCancelled { break }
                try? await sink.send(frame)
            }
        }
    }
}
