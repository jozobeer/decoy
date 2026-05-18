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
            // checkInFailed (host が立っていない / entitlement 拒否) ―
            // fallback timer のままにしておく。本 task は終わる。
            return
        }
        // stream が自然終了 (receiver.stop() / recv error) したら fallback
        // を復帰させる。再 connect の試みは v1 では入れない ― receiver の
        // events stream を別 PR で追加してから扱う。
        timerQueue.async { [weak self] in
            guard let self else { return }
            guard timer == nil else { return }
            startFallbackTimer()
        }
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
            // `.hostTime` clocking なので Mach uptime 由来の nanoseconds を渡す。
            let hostTimeNs = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
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
