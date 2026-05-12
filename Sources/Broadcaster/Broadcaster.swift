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
            // Drain any in-flight teardown first — concurrent
            // .startDecoy may still be awaiting stopRouting(), which
            // would leave `routing` non-nil and make startRouting()
            // no-op. stopRouting() on a nil/finished routing is a
            // cheap no-op, so this is safe to always call.
            await stopRouting()
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

    /// Cancel the active routing task and wait for it to fully wind down.
    /// `routing` stays non-nil during the await so a concurrent
    /// `startRouting()` (via actor re-entrancy) can't spawn a second
    /// task while the old one is still draining. Identity-check at the
    /// end so a stop+restart sequence doesn't clobber the new task.
    private func stopRouting() async {
        guard let task = routing else { return }
        task.cancel()
        await task.value
        if routing == task {
            routing = nil
        }
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
