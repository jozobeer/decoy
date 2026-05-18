import Domain
import Foundation

/// CMIO Camera Extension 側の IPC 受信 actor。`bootstrap_check_in` で
/// service name を launchd に登録し、`mach_msg` recv loop で host
/// (`MachPortFrameTransport`) から送られた IOSurface ref を materialize
/// して `Frame` を多重 subscriber に fan-out する。
///
/// 構造：
///
/// - state-machine + 多重 subscriber broadcast + materialize 失敗の drop
///   policy は本ファイル (純粋ロジック・全 path テスト covered)。
/// - OS-direct な Mach API 呼び出し (`bootstrap_check_in` / `mach_msg` /
///   `IOSurfaceLookupFromMachPort`) は `MachPortFrameReceiver+Live.swift`
///   経路 (`BootstrapMachPortCheckIn` / `IOSurfaceLookupMaterializer`)
///   に切り出して codecov ignore 対象 — see
///   `.claude/rules/coverage-ignored-modules.md`。
///
/// 状態遷移：
///
/// ```
/// idle ──start()──> starting ──ok──> listening
///                       │
///                       └──fail──> stopped
///                                     │
/// listening ──stop()──> stopped ──start()──┘
///        │
///        └── server stream ends ──> stopped
/// ```
///
/// - 初期状態は `.idle`。新規 subscriber には initial event なし
///   (Frame stream は「届いた frame」だけを流す pull-only ストリーム)。
/// - `start()` 成功で `.listening` ― server.messages を consume する
///   background task が走り、incoming message ごとに materializer を
///   呼んで Frame を broadcast する。
/// - 既に starting / listening なら `start()` は no-op。並行呼び出しは
///   `.starting` 状態で短絡され、check-in は一度しか走らない。
/// - `stop()` ― state を `.stopped` にして、consume task を cancel、
///   server.stop() を await。subscriber stream は finish させる。
/// - server stream が自然終了 (recv error 含む) しても state は `.stopped`
///   に倒し、subscriber stream を finish させる。再 `start()` 可能。
/// - materialize 失敗 (`IOSurfaceLookupFromMachPort` 失敗等) は frame を
///   drop して loop を継続 ― 1 frame の損失で receiver を殺さない
///   real-time pipeline の方針。失敗 event は v1 では露出しない (PR 5 で
///   `events` stream 追加検討)。
public actor MachPortFrameReceiver {
    private enum State {
        case idle
        case starting
        case listening
        case stopped
    }

    private let serviceName: String
    private let server: any MachPortServer
    private let materializer: any IOSurfaceMaterializer
    private var state: State = .idle
    private var continuations: [UUID: AsyncStream<Frame>.Continuation] = [:]
    private var listenTask: Task<Void, Never>?

    public init(
        serviceName: String,
        server: any MachPortServer,
        materializer: any IOSurfaceMaterializer
    ) {
        self.serviceName = serviceName
        self.server = server
        self.materializer = materializer
    }
}

extension MachPortFrameReceiver {
    /// 多重 subscriber 対応の Frame stream。subscribe 毎に独立した
    /// continuation を発行し、`broadcast(_:)` で全員に同じ Frame を
    /// 流す。subscriber が消えたら `onTermination` で自分の continuation
    /// を table から外す。
    public var frames: AsyncStream<Frame> {
        AsyncStream { continuation in
            let id = UUID()
            continuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id: id) }
            }
        }
    }

    public func start() async throws {
        switch state {
        case .starting, .listening:
            return
        case .idle, .stopped:
            state = .starting
        }
        do {
            let stream = try await server.messages(serviceName: serviceName)
            // Race: caller can invoke stop() while we're suspended on the
            // await above. If state has been moved out of .starting, we
            // honour that ― drop the freshly-acquired stream (its
            // onTermination releases the receive right) instead of
            // springing back to .listening and ignoring the stop.
            switch state {
            case .starting:
                state = .listening
                listenTask = Task { [weak self] in
                    await self?.consume(stream: stream)
                }
            case .idle, .listening, .stopped:
                return
            }
        } catch {
            // Same race for the failure path: only flip to .stopped if the
            // caller hasn't already done so (state == .starting). Always
            // finish subscriber streams ― `for await` consumers should
            // not wait forever when startup definitively failed (matches
            // `stop()` and stream-end paths).
            if case .starting = state {
                state = .stopped
            }
            finishAllContinuations()
            throw error
        }
    }

    public func stop() async {
        switch state {
        case .idle, .stopped:
            return
        case .starting, .listening:
            state = .stopped
        }
        listenTask?.cancel()
        listenTask = nil
        finishAllContinuations()
        await server.stop()
    }
}

private extension MachPortFrameReceiver {
    func consume(stream: AsyncThrowingStream<IncomingFrameMessage, Error>) async {
        do {
            for try await message in stream {
                await deliver(message: message)
            }
            await handleStreamEnded()
        } catch {
            await handleStreamEnded()
        }
    }

    func deliver(message: IncomingFrameMessage) async {
        do {
            let frame = try await materializer.frame(from: message)
            broadcast(frame)
        } catch {
            // materialize 失敗は 1 frame drop ― loop は継続。
        }
    }

    func handleStreamEnded() async {
        switch state {
        case .idle, .stopped:
            return
        case .starting, .listening:
            state = .stopped
            finishAllContinuations()
        }
    }

    func broadcast(_ frame: Frame) {
        continuations.values.forEach { $0.yield(frame) }
    }

    func finishAllContinuations() {
        continuations.values.forEach { $0.finish() }
        continuations.removeAll()
    }

    func removeContinuation(id: UUID) {
        continuations.removeValue(forKey: id)
    }
}

