import Dependencies
import Foundation

/// host (Broadcaster 配下) から extension (Camera Extension) へ frame を
/// 渡す IPC port。
///
/// 役割：
///
/// - `connect()` で extension との通信路を確立する。Mach port impl では
///   bootstrap で extension の receive port を lookup し、send port を
///   取得する。
/// - `send(_:)` で frame を extension に push する。Mach port impl では
///   IOSurface ref を Mach message に載せて投げる (serialize / copy なし)。
/// - 通信状態の変化は `events` AsyncStream で push される ―
///   `.connected` / `.disconnected` / `.sendFailed`。Broadcaster の
///   `.sendFailed` event 経路に直結する。
/// - `disconnect()` で send port を release する。
///
/// 契約：
///
/// - `connect()` を複数回呼んでも、既に接続済みなら no-op (重複 connect
///   不可)。
/// - `send(_:)` 前に `connect()` していなければ throw する。
/// - `disconnect()` 後に `send(_:)` を呼ぶと throw する。
/// - `events` stream は subscribe 時点の最新状態を初回 emit してから
///   遷移を流す。subscriber が複数いても各々が同じ値列を受け取る。
public protocol FrameTransport: Sendable {
    var events: AsyncStream<FrameTransportEvent> { get async }
    func connect() async throws
    func disconnect() async
    func send(_ frame: Frame) async throws
}

/// `FrameTransport.events` が流す値。
public enum FrameTransportEvent: Sendable, Equatable {
    /// `connect()` が成功し、send port が握れた状態。
    case connected
    /// 切断状態 ― まだ connect していないか、相手 (extension) が落ちた。
    case disconnected
    /// frame 送信に失敗した。Broadcaster の `.sendFailed` 経路に伝播する。
    case sendFailed(reason: String)
}

/// `FrameTransport` の操作で起きうるエラー。
public enum FrameTransportError: Error, Equatable, Sendable {
    /// 一度も `connect()` を呼んでいない状態で `send(_:)` を呼んだ。
    case notConnected
    /// `connect()` → `disconnect()` の後に `send(_:)` を呼んだ。
    /// caller は「接続が切れた」と「まだ接続していない」を区別できる ―
    /// Mach port impl でも extension 側がクラッシュした場合は本ケースに
    /// 寄せる (extension 側 down → host の send が落ちる経路)。
    case disconnectedDuringSend
    /// IPC 層 (Mach port / IOSurface) でのエラー。
    case transport(reason: String)
}

public enum FrameTransportKey: TestDependencyKey {
    public static let testValue: any FrameTransport = UnimplementedFrameTransport()
}

extension DependencyValues {
    public var frameTransport: any FrameTransport {
        get { self[FrameTransportKey.self] }
        set { self[FrameTransportKey.self] = newValue }
    }
}

private struct UnimplementedFrameTransport: FrameTransport {
    var events: AsyncStream<FrameTransportEvent> {
        get async {
            reportIssue(#"@Dependency(\.frameTransport)"#)
            return AsyncStream { $0.finish() }
        }
    }
    func connect() async throws {
        reportIssue(#"@Dependency(\.frameTransport)"#)
    }
    func disconnect() async {
        reportIssue(#"@Dependency(\.frameTransport)"#)
    }
    func send(_ frame: Frame) async throws {
        reportIssue(#"@Dependency(\.frameTransport)"#)
    }
}
