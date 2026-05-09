import Domain

public actor Broadcaster {
    public private(set) var state: OutputMode

    public init(state: OutputMode = .live) {
        self.state = state
    }

    public func handle(_ command: AppCommand) {
        // tdd-impl phase: not yet implemented
    }
}
