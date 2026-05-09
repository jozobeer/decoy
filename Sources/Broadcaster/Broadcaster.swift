import Domain

public actor Broadcaster {
    public private(set) var state: OutputMode

    public init(state: OutputMode = .live) {
        self.state = state
    }

    public func handle(_ command: AppCommand) {
        switch command {
        case .startDecoy(let mode):
            state = .playback(mode)
        case .returnToLive:
            state = .live
        case .startRecording, .stopRecording:
            break
        }
    }
}
