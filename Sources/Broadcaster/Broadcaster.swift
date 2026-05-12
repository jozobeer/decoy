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
            let task = Self.makeRoutingTask(source: cameraSource, sink: virtualCameraSink)
            self.routing = task
            Task { [weak self] in
                _ = await task.value
                await self?.routingDidComplete(task)
            }
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

    public func shutdown() async {
        await stopRouting()
    }
}

extension Broadcaster {
    private func startRouting() {
        guard routing == nil else { return }
        let task = Self.makeRoutingTask(source: cameraSource, sink: virtualCameraSink)
        routing = task
        Task { [weak self] in
            _ = await task.value
            await self?.routingDidComplete(task)
        }
    }

    private func stopRouting() async {
        let task = routing
        routing = nil
        task?.cancel()
        await task?.value
    }

    /// Called when a routing task finishes — naturally (source closed)
    /// or via cancellation. Only clears `routing` when the completing
    /// task is the one we currently track, so a stop+restart sequence
    /// doesn't accidentally drop the new task.
    private func routingDidComplete(_ task: Task<Void, Never>) {
        if routing == task {
            routing = nil
        }
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
