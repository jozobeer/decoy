import Domain
import Foundation

/// Opaque send-right token returned by `MachPortLookup` and consumed by
/// `MachPortSender`. Wraps the underlying `mach_port_t` so the
/// state-machine layer never touches raw Mach types directly — this
/// keeps `MachPortFrameTransport` covered by tests without dragging
/// Mach into the actor itself.
public struct MachPortToken: Sendable, Equatable {
    public let raw: UInt32

    public init(raw: UInt32) {
        self.raw = raw
    }
}

/// Service-name → send-right lookup. The live impl calls
/// `bootstrap_look_up`; the in-process fake used by tests resolves
/// names from a dictionary that the receiver side has registered.
public protocol MachPortLookup: Sendable {
    func lookUp(serviceName: String) async throws -> MachPortToken
}

/// Sender for one `Frame` over a previously-resolved send right, plus
/// release of that send right on disconnect. The live impl materialises
/// an `IOSurface` from `Frame.pixelData` (via `IOSurfaceFactory`), turns
/// it into a Mach port via `IOSurfaceCreateMachPort`, and ships it with
/// `mach_msg`. Confined to a separate protocol so tests can substitute
/// an in-process recorder without touching OS primitives.
public protocol MachPortSender: Sendable {
    func send(frame: Frame, via port: MachPortToken) async throws
    func release(port: MachPortToken) async
}

/// Errors the lookup / sender layer can raise. The actor wraps these
/// into `FrameTransportError.transport(reason:)` before re-throwing,
/// so callers see the Domain-level error type while still getting the
/// raw cause for logging.
public enum MachPortTransportError: Error, Sendable, Equatable {
    case lookupFailed(serviceName: String, code: Int)
    case sendFailed(code: Int)
}
