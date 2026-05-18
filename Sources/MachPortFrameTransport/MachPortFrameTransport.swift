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
///   `MachPortFrameTransport+Live.swift` に切り出して codecov ignore
///   対象 — see `.claude/rules/coverage-ignored-modules.md`。
///
/// 状態管理：
///
/// - 初期状態は `.disconnected`、新規 subscriber には initial として
///   emit する。
/// - `connect()` 成功で `.connected` を broadcast。失敗時は
///   `.sendFailed(reason:)` を broadcast したうえで
///   `FrameTransportError.transport(reason:)` を throw。
/// - 既に connected なら `connect()` は no-op。
/// - `send(_:)` は state が `.connected` でなければ
///   `FrameTransportError.notConnected` を throw。送信失敗時は
///   `.sendFailed(reason:)` broadcast + `FrameTransportError.transport(...)`
///   を throw。
/// - `disconnect()` は send port を release し、状態を
///   `.disconnected` に戻す。
public actor MachPortFrameTransport {
    private let serviceName: String
    private let lookup: any MachPortLookup
    private let sender: any MachPortSender
    private var connectedPort: MachPortToken?
    private var lastEvent: FrameTransportEvent = .disconnected
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
                continuation.yield(lastEvent)
                continuations[id] = continuation
                continuation.onTermination = { [weak self] _ in
                    Task { await self?.removeContinuation(id: id) }
                }
            }
        }
    }

    public func connect() async throws {
        guard connectedPort == nil else { return }
        do {
            let port = try await lookup.lookUp(serviceName: serviceName)
            connectedPort = port
            broadcast(.connected)
        } catch {
            let reason = "lookup failed: \(error)"
            broadcast(.sendFailed(reason: reason))
            throw FrameTransportError.transport(reason: reason)
        }
    }

    public func disconnect() async {
        guard let port = connectedPort else { return }
        await sender.release(port: port)
        connectedPort = nil
        broadcast(.disconnected)
    }

    public func send(_ frame: Frame) async throws {
        guard let port = connectedPort else {
            throw FrameTransportError.notConnected
        }
        do {
            try await sender.send(frame: frame, via: port)
        } catch {
            let reason = "send failed: \(error)"
            broadcast(.sendFailed(reason: reason))
            throw FrameTransportError.transport(reason: reason)
        }
    }
}

private extension MachPortFrameTransport {
    func broadcast(_ event: FrameTransportEvent) {
        lastEvent = event
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}
