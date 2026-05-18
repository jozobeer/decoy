import CoreMedia
import CoreMediaIO
import Domain
import Foundation
import FrameSampleBufferAdapter
import MachPortFrameReceiver

/// `CMIOExtensionStreamSource` 実装 ― CMIO の stream に frame を流し込む。
///
/// 二系統の送信元を持つ：
///
/// 1. **MachPortFrameReceiver** ― host (`MachPortFrameTransport`) から
///    Mach port + IOSurface ref で受信した実 frame。host が live のときの
///    第一義経路。`startStream()` で receiver を起動し、`frames` stream を
///    consume して `FrameSampleBufferAdapter` で `CMSampleBuffer` に変換、
///    `stream.send(...)` に push する。
///
/// 2. **LogoFrameRenderer fallback** ― host が立っていない / 起動直後で
///    `bootstrap_check_in` が失敗するときの代替経路。固定パターン (Decoy
///    ロゴ on teal) を 30fps で出して client (Zoom 等) が真っ黒にならない
///    ようにする。receiver が初回 frame を流し始めたら自動で停止し、
///    receiver の stream が終端したら復帰する。
///
/// state mutations は `timerQueue` (serial DispatchQueue) に集約して
/// CMIO host の呼び出しと receiver task からの callback を排他する。
final class DecoyCameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource, @unchecked Sendable {
    private(set) lazy var stream: CMIOExtensionStream = CMIOExtensionStream(
        localizedName: "Decoy",
        streamID: UUID(),
        direction: .source,
        clockType: .hostTime,
        source: self
    )
    private let renderer = LogoFrameRenderer(width: 1280, height: 720)
    private let timerQueue = DispatchQueue(label: "beer.jozo.decoy.CameraExtension.timer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
    private var receiver: MachPortFrameReceiver?
    private var receiverTask: Task<Void, Never>?
    private let format: CMIOExtensionStreamFormat

    override init() {
        format = CMIOExtensionStreamFormat(
            formatDescription: LogoFrameRenderer.formatDescription(width: 1280, height: 720),
            maxFrameDuration: CMTime(value: 1, timescale: 30),
            minFrameDuration: CMTime(value: 1, timescale: 30),
            validFrameDurations: [CMTime(value: 1, timescale: 30)]
        )
        super.init()
    }

    var formats: [CMIOExtensionStreamFormat] { [format] }

    var availableProperties: Set<CMIOExtensionProperty> {
        [.streamActiveFormatIndex, .streamFrameDuration]
    }

    func streamProperties(forProperties properties: Set<CMIOExtensionProperty>) throws -> CMIOExtensionStreamProperties {
        let result = CMIOExtensionStreamProperties(dictionary: [:])
        if properties.contains(.streamActiveFormatIndex) {
            result.activeFormatIndex = 0
        }
        if properties.contains(.streamFrameDuration) {
            result.frameDuration = CMTime(value: 1, timescale: 30)
        }
        return result
    }

    func setStreamProperties(_ streamProperties: CMIOExtensionStreamProperties) throws {}

    func authorizedToStartStream(for client: CMIOExtensionClient) -> Bool { true }

    func startStream() throws {
        timerQueue.sync {
            // 既に動いている場合は何もしない ― 重複 receiverTask / timer で
            // 旧 instance が漏れて stopStream() で止まらない bug を防ぐ。
            guard timer == nil, receiverTask == nil else { return }
            startFallbackTimer()
            startReceiver()
        }
    }

    func stopStream() throws {
        timerQueue.sync {
            stopFallbackTimer()
            stopReceiver()
        }
    }
}

private extension DecoyCameraExtensionStreamSource {
    func startFallbackTimer() {
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: .nanoseconds(33_333_333), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.emitFallbackFrame()
        }
        self.timer = timer
        timer.resume()
    }

    func stopFallbackTimer() {
        timer?.cancel()
        timer = nil
    }

    func startReceiver() {
        let receiver = MachPortFrameReceiver.live(serviceName: FrameTransportServiceName.mach)
        self.receiver = receiver
        receiverTask = Task { [weak self] in
            await self?.consumeReceiver(receiver)
        }
    }

    func stopReceiver() {
        receiverTask?.cancel()
        receiverTask = nil
        guard let receiver else { return }
        self.receiver = nil
        // actor の `stop()` は async。stream-stop の呼び出し元 (CMIO host)
        // は sync なので detached Task に逃がす ― stop 完了を待つ必要は
        // ない (cancel 済み task が次の sleep / await から抜けるまでは
        // 数 ms オーダー)。
        Task { await receiver.stop() }
    }

    func consumeReceiver(_ receiver: MachPortFrameReceiver) async {
        do {
            // subscribe → start の順 ― start() 直後に来る frame を取りこぼさない。
            let frames = await receiver.frames
            try await receiver.start()
            for await frame in frames {
                pushReceivedFrame(frame)
            }
        } catch {
            // checkInFailed (host が立っていない / entitlement 拒否) や
            // CancellationError ― receiver / task の参照を落として
            // 次回 startStream() で retry できる状態に戻す。
            timerQueue.async { [weak self] in
                self?.clearReceiverState()
            }
            return
        }
        // for await が抜けた = stream 終端。explicit stop (stopReceiver から
        // Task cancel された) と server-side 終端 (host crash / recv error) を
        // 区別する ― 前者は stream-stop semantics 通り fallback も復帰させない、
        // 後者は client が真っ黒にならないように fallback timer を復帰させる。
        let cancelled = Task.isCancelled
        timerQueue.async { [weak self] in
            guard let self else { return }
            clearReceiverState()
            guard !cancelled else { return }
            guard timer == nil else { return }
            startFallbackTimer()
        }
    }

    /// `receiverTask` / `receiver` を nil 化する。`stopReceiver` 経由で先に
    /// clear 済みの場合は no-op になる。consumeReceiver の終了経路 (catch
    /// / 自然終了) の後始末用。
    func clearReceiverState() {
        receiverTask = nil
        receiver = nil
    }

    func pushReceivedFrame(_ frame: Frame) {
        // 初回 remote frame が来たら fallback timer を停止する ― receiver と
        // timer の両方が `stream.send` を叩くと client が重複 timestamp で
        // drop / freeze する。
        timerQueue.async { [weak self] in
            self?.stopFallbackTimer()
        }
        do {
            let sampleBuffer = try FrameSampleBufferAdapter.sampleBuffer(from: frame)
            // `.hostTime` clocking ― CMSampleBuffer の PTS と `hostTimeInNanoseconds`
            // は同じ Mach uptime timeline で揃える。CMSampleBuffer の PTS は
            // `frame.presentationTime` から組み立てているので、send 引数も
            // それを nanoseconds に翻訳した値で渡す ― "now" を渡すと IPC
            // latency 分のズレで client が drop / 早送り判定する。
            let hostTimeNs = UInt64(max(0, (frame.presentationTime * Double(NSEC_PER_SEC)).rounded()))
            stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTimeNs)
        } catch {
            // 1 frame drop ― receive loop は継続。30fps なので 1 frame の
            // 損失は client にとってほぼ不可視。
        }
    }

    func emitFallbackFrame() {
        guard let pixelBuffer = renderer.nextFrame() else { return }
        guard let sampleBuffer = renderer.sampleBuffer(from: pixelBuffer) else { return }
        // `.hostTime` clocking なので Mach uptime 由来の nanoseconds を渡す。
        // 0 を渡すと全 frame が同 timestamp 扱いになり client (Zoom 等) が
        // drop / freeze する。
        let hostTimeNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
        stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: hostTimeNs)
    }
}
