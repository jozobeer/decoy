import Domain
import Foundation

/// Opaque receive / send-right token shared with the host-side
/// `MachPortFrameTransport`. The receiver actor never touches raw Mach
/// types directly — incoming surface ports arrive as tokens and are
/// resolved to `Frame` by the materializer.
public struct ReceiverMachPortToken: Sendable, Equatable {
    public let raw: UInt32

    public init(raw: UInt32) {
        self.raw = raw
    }
}

/// One incoming message off the Mach port recv loop. Mirrors the
/// host-side `FrameMachMessage` wire format
/// (`Sources/MachPortFrameTransport/MachPortMessageSender.swift`): the
/// surface port name plus frame metadata the host couldn't recover
/// from the surface alone (presentation time). `width` / `height` are
/// carried for sanity (the materializer can also read them from the
/// surface). Caller (the materializer) is responsible for resolving
/// the port + releasing the send right; the actor itself never owns
/// the right.
public struct IncomingFrameMessage: Sendable, Equatable {
    public let surfacePort: ReceiverMachPortToken
    public let presentationTime: TimeInterval
    public let width: Int
    public let height: Int

    public init(
        surfacePort: ReceiverMachPortToken,
        presentationTime: TimeInterval,
        width: Int,
        height: Int
    ) {
        self.surfacePort = surfacePort
        self.presentationTime = presentationTime
        self.width = width
        self.height = height
    }
}

/// `bootstrap_check_in(3)` + `mach_msg` recv loop port. The live impl
/// registers `serviceName` with launchd and yields one message per
/// `MACH_RCV_MSG` until `stop()` is invoked or the receive right is
/// destroyed. Stream termination signals "no more messages" — the
/// actor reacts by moving to `.stopped`.
///
/// Throwing variant is used so check-in failures (denied entitlement,
/// duplicate registration) surface synchronously, while recv-loop
/// failures terminate the stream with an error.
public protocol MachPortServer: Sendable {
    func messages(serviceName: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error>
    func stop() async
}

/// Surface-port → `Frame` resolution. The live impl calls
/// `IOSurfaceLookupFromMachPort`, locks the surface for read, copies
/// pixel bytes into a `Frame.pixelData` `Data`, then releases the
/// Mach send right via `mach_port_deallocate`. Confined to a separate
/// protocol so the actor can be tested with an in-process fake that
/// returns prebuilt frames without touching IOSurface at all.
public protocol IOSurfaceMaterializer: Sendable {
    func frame(from message: IncomingFrameMessage) async throws -> Frame
}

/// Errors the receiver layer can raise. `checkInFailed` is thrown
/// synchronously from `start()`; `recvFailed` and `materializationFailed`
/// arrive via the stream's error terminator and are surfaced through
/// `Frame` consumers only after the actor moves to `.stopped`.
public enum MachPortReceiverError: Error, Sendable, Equatable {
    case checkInFailed(serviceName: String, code: Int)
    case recvFailed(code: Int)
    case surfaceLookupFailed(code: Int)
}
