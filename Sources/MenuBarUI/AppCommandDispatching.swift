import AppCommandDispatcher
import Domain

/// Thin protocol over `AppCommandDispatcher.dispatch`. The menu-bar
/// view-model only needs the dispatch verb — wrapping it in a protocol
/// lets tests substitute a recording spy without standing up a full
/// Recorder + Broadcaster pair.
public protocol AppCommandDispatching: Sendable {
    func dispatch(_ command: AppCommand) async
}

extension AppCommandDispatcher: AppCommandDispatching {}
