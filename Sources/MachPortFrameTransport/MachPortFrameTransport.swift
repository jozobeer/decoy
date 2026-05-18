import Domain
import Foundation

/// `FrameTransport` の host (Decoy.app) 側実装。Mach port を介して
/// extension (Camera Extension) に frame を送る。
///
/// 構造：
///
/// - state-machine + 多重 subscriber broadcast は本ファイル
///   (純粋ロジック・全 path テスト covered)。
/// - OS-direct な Mach API 呼び出し (`bootstrap_look_up` /
///   `IOSurfaceCreateMachPort` / `mach_msg`) は
///   `MachPortFrameTransport+Live.swift` 経路 (`BootstrapMachPortLookup`
///   / `MachPortMessageSender`) に切り出して codecov ignore 対象 — see
///   `.claude/rules/coverage-ignored-modules.md`。
///
/// 状態遷移：
///
/// ```
/// neverConnected ──connect()──> connecting ──ok──> connected
///                                      │
///                                      └──fail──> disconnected
///                                                       │
/// connected ──disconnect()──> disconnected ──connect()──┘
///        │
///        └── send() with destinationLost ──> disconnected
/// ```
///
/// - 初期状態は `.neverConnected` ― 新規 subscriber には initial として
///   `.disconnected` を emit する。
/// - `connect()` 成功で `.connected(token)` + broadcast `.connected`。
///   失敗時は `.disconnected` に遷移して `.sendFailed` を broadcast し
///   `FrameTransportError.transport(reason:)` を throw。
/// - 既に connecting / connected なら `connect()` は no-op。並行呼び出しは
///   `connecting` 状態で短絡され、lookup は一度しか走らない (actor の
///   逐次性 + state guard で reentrancy 安全)。
/// - `send(_:)` は state に応じて以下を throw：
///   - `.neverConnected` / `.connecting` ― `FrameTransportError.notConnected`
///   - `.disconnected` ― `FrameTransportError.disconnectedDuringSend`
///     (一度は接続したが切れた、を notConnected と区別する)
///   - `.connected` ― sender に委譲。`destinationLost` (receiver port
///     消失 = `MACH_SEND_INVALID_DEST`) は state を `.disconnected` に
///     遷移させて broadcast `.disconnected` したうえで
///     `FrameTransportError.disconnectedDuringSend` を throw。それ以外の
///     失敗は `.sendFailed(reason:)` broadcast + `.transport(reason:)`
///     を throw。
/// - `disconnect()` は state を先に `.disconnected` にして broadcast して
///   から send port を release する。release は actor の suspension を
///   伴うため、その間に発火する `send(_:)` は新 state を見て
///   `.disconnectedDuringSend` を返すのが正しい (port は既に解放経路)。
public actor MachPortFrameTransport {
    private enum State {
        case neverConnected
        case connecting
        case connected(MachPortToken)
        case disconnected
    }

    private let serviceName: String
    private let lookup: any MachPortLookup
    private let sender: any MachPortSender
    private var state: State = .neverConnected
    private var continuations: [UUID: AsyncStream<FrameTransportEvent>.Continuation] = [:]

    public init(
        serviceName: String,
        lookup: any MachPortLookup,
        sender: any MachPortSender
    ) {
        self.serviceName = serviceName
        self.lookup = lookup
        self.sender = sender
    }
}

extension MachPortFrameTransport: FrameTransport {
    public var events: AsyncStream<FrameTransportEvent> {
        get async {
            AsyncStream { continuation in
                let id = UUID()
                continuation.yield(currentEvent)
                continuations[id] = continuation
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeContinuation(id: id) }
                }
            }
        }
    }

    public func connect() async throws {
        switch state {
        case .connecting, .connected:
            return
        case .neverConnected, .disconnected:
            state = .connecting
        }
        do {
            let port = try await lookup.lookUp(serviceName: serviceName)
            state = .connected(port)
            broadcast(.connected)
        } catch {
            state = .disconnected
            let reason = "lookup failed: \(error)"
            broadcast(.sendFailed(reason: reason))
            throw FrameTransportError.transport(reason: reason)
        }
    }

    public func disconnect() async {
        guard case .connected(let port) = state else { return }
        state = .disconnected
        broadcast(.disconnected)
        await sender.release(port: port)
    }

    public func send(_ frame: Frame) async throws {
        switch state {
        case .neverConnected, .connecting:
            throw FrameTransportError.notConnected
        case .disconnected:
            throw FrameTransportError.disconnectedDuringSend
        case .connected(let port):
            try await sendOnConnectedPort(frame: frame, via: port)
        }
    }
}

private extension MachPortFrameTransport {
    var currentEvent: FrameTransportEvent {
        switch state {
        case .connected:
            return .connected
        case .neverConnected, .connecting, .disconnected:
            return .disconnected
        }
    }

    func sendOnConnectedPort(frame: Frame, via port: MachPortToken) async throws {
        do {
            try await sender.send(frame: frame, via: port)
        } catch let machError as MachPortTransportError {
            switch machError {
            case .destinationLost:
                try handleDestinationLost()
            case .lookupFailed, .sendFailed:
                throw broadcastAndMapTransportError(machError)
            }
        } catch {
            throw broadcastAndMapTransportError(error)
        }
    }

    func handleDestinationLost() throws {
        // receiver port が消えた ― 接続は実質切れたので state を
        // disconnected に遷移させ、caller には disconnectedDuringSend を
        // 返して notConnected と区別させる。race で既に disconnect が
        // 走っていた場合は重複 broadcast を避ける。
        guard case .connected = state else {
            throw FrameTransportError.disconnectedDuringSend
        }
        state = .disconnected
        broadcast(.disconnected)
        throw FrameTransportError.disconnectedDuringSend
    }

    func broadcastAndMapTransportError(_ error: Error) -> FrameTransportError {
        let reason = "send failed: \(error)"
        broadcast(.sendFailed(reason: reason))
        return FrameTransportError.transport(reason: reason)
    }

    func broadcast(_ event: FrameTransportEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
