import CoreMedia
import CoreMediaIO
import Foundation

/// `CMIOExtensionStreamSource` 実装 ― 実際の frame を送出する stream。
///
/// `startStream()` でタイマーを起動し、1/30 秒ごとに `LogoFrameRenderer` が
/// 生成する固定パターン (Decoy ロゴ on teal) を `CMSampleBuffer` に包んで
/// `stream.send(...)` で push する。`stopStream()` でタイマーを止める。
///
/// IPC で host からの frame を受け取る変更は #43 で追加 ― 本 issue では
/// extension 単独で動くテストパターン出力に scope を絞る。
final class DecoyCameraExtensionStreamSource: NSObject, CMIOExtensionStreamSource {
    private(set) var stream: CMIOExtensionStream!
    private weak var owningDevice: CMIOExtensionDevice?
    private let renderer = LogoFrameRenderer(width: 1280, height: 720)
    private let timerQueue = DispatchQueue(label: "beer.jozo.decoy.CameraExtension.timer", qos: .userInteractive)
    private var timer: DispatchSourceTimer?
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

    func bind(to device: CMIOExtensionDevice) {
        owningDevice = device
        let streamID = UUID()
        stream = CMIOExtensionStream(
            localizedName: "Decoy",
            streamID: streamID,
            direction: .source,
            clockType: .hostTime,
            source: self
        )
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
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(deadline: .now(), repeating: .milliseconds(33), leeway: .milliseconds(5))
        timer.setEventHandler { [weak self] in
            self?.emitFrame()
        }
        self.timer = timer
        timer.resume()
    }

    func stopStream() throws {
        timer?.cancel()
        timer = nil
    }
}

extension DecoyCameraExtensionStreamSource {
    private func emitFrame() {
        guard let stream else { return }
        guard let pixelBuffer = renderer.nextFrame() else { return }
        guard let sampleBuffer = LogoFrameRenderer.sampleBuffer(from: pixelBuffer) else { return }
        stream.send(sampleBuffer, discontinuity: [], hostTimeInNanoseconds: 0)
    }
}
