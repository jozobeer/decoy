import Dependencies
import Domain

/// Fan-out point for `AppCommand`. UI / keyboard adapters publish one
/// `AppCommand`; the dispatcher hands it concurrently to both
/// `RecorderUseCase` and `BroadcasterUseCase` so each actor can decide
/// what (if anything) the command means for its own state.
///
/// Why `struct` instead of `actor`: the dispatcher holds zero mutable
/// state of its own — it forwards. Both targets are already actors and
/// own their own isolation; the dispatcher has nothing to protect. An
/// extra layer of actor isolation here would only add an unnecessary
/// hop without buying any invariant.
///
/// Concurrency model: `async let` spawns two child tasks that hop into
/// the recorder and broadcaster actors independently. `dispatch`
/// returns only after both have completed their `handle` call, which is
/// the structural guarantee callers want — "the command has been
/// observed by both sides".
public struct AppCommandDispatcher: Sendable {
    @Dependency(\.recorder) private var recorder
    @Dependency(\.broadcaster) private var broadcaster

    public init() {}

    public func dispatch(_ command: AppCommand) async {
        async let r: Void = recorder.handle(command)
        async let b: Void = broadcaster.handle(command)
        _ = await (r, b)
    }
}
