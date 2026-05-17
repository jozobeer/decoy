import Domain

/// `VirtualCameraSink` の本番実装 ― `FrameTransport` (#43) 経由で
/// Camera Extension に frame を送る adapter。
///
/// 役割：
///
/// - `init(transport:)` で IPC 層 (`FrameTransport`) を注入される。
///   live wiring では Mach port + IOSurface 実装、テストでは
///   `InMemoryFrameTransport` を渡す。
/// - `send(_:)` で frame を transport に push する。transport が
///   throw した場合はそのまま伝播 ― `Broadcaster` の `.sendFailed`
///   event 経路に乗る。
/// - 初回 `send(_:)` のタイミングで遅延 connect ― `init` 内では IPC
///   接続を張らない (init は同期、connect は async なので必然)。
///
/// 契約：
///
/// - `send(_:)` を複数回呼んでも、接続済みなら都度 `connect()` は
///   走らない (transport 側で idempotent)。
/// - transport が `.notConnected` を返した場合は本 adapter で
///   自動的に `connect()` を試みる ― caller が接続を意識せず
///   `VirtualCameraSink` として使えるようにする。
/// - `connect()` 自体が失敗した場合はそのエラーを伝播する。
///
/// 後続 (#33 stage 2): `CameraExtensionInstaller` (#44) の status を
/// 購読し、`needsApproval` / `notInstalled` 中は send を諦めて
/// `.sendFailed` を即 throw する経路を追加する。
public actor CMIOVirtualCameraSink {
    private let transport: any FrameTransport

    public init(transport: any FrameTransport) {
        self.transport = transport
    }
}

extension CMIOVirtualCameraSink: VirtualCameraSink {
    public func send(_ frame: Frame) async throws {
        do {
            try await transport.send(frame)
        } catch FrameTransportError.notConnected {
            try await transport.connect()
            try await transport.send(frame)
        }
    }
}
