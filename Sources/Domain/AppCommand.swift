public enum AppCommand: Sendable, Equatable {
    case startRecording
    case stopRecording
    case startDecoy(PlaybackMode)
    case returnToLive
}
