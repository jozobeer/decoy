import Domain

public actor Recorder {
    public private(set) var state: RecordingState

    public init(state: RecordingState = .idle) {
        self.state = state
    }

    public func handle(_ command: AppCommand) {
        switch command {
        case .startRecording:
            state = .recording
        case .stopRecording:
            state = .idle
        case .startDecoy, .returnToLive:
            break
        }
    }
}
