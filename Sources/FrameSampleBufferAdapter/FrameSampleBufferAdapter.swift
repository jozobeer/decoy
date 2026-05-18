import CoreMedia
import CoreVideo
import Domain
import Foundation

/// `Frame` (Entity ― 純粋データ) を CMIO Camera Extension の
/// `CMIOExtensionStream.send` が要求する `CMSampleBuffer` に変換する純粋ロジック。
///
/// 役割：
///
/// - host 側 `MachPortFrameTransport` → `MachPortFrameReceiver` を経て受信した
///   `Frame.pixelData` を `CVPixelBuffer` に詰め直し、`presentationTime`
///   (`TimeInterval` = 秒) を `CMTime` (`HOST_TIME_PER_SEC` 基準の nanoseconds)
///   に翻訳して `CMSampleBuffer` を組み立てる。
/// - extension 側の `CMIOExtensionStreamClock = .hostTime` 契約に合わせて
///   PTS は `clock_gettime_nsec_np(CLOCK_UPTIME_RAW)` 由来の時間軸で渡す前提。
///   呼び出し側 (extension の stream source) は `Frame.presentationTime` を
///   その時間軸の秒で組み立てる責務を負う。
///
/// `+Live.swift` 経路には載せない理由：CoreVideo / CoreMedia 経由の変換は
/// in-process で完結しユニットテスト可能 ― OS-direct な Mach API や launchd
/// 経由の registration を伴わない。frame 1 枚で全 path を exercise できる
/// ので coverage 対象として残す。
public enum FrameSampleBufferAdapter {}

extension FrameSampleBufferAdapter {
    /// `Frame` を 1 枚の `CMSampleBuffer` に変換する。失敗した step を
    /// `FrameSampleBufferAdapterError` で伝播する ― 強制 unwrap や silent
    /// drop は行わない (Stream source 側で 1 frame drop の判断を委ねる)。
    public static func sampleBuffer(from frame: Frame) throws -> CMSampleBuffer {
        try validate(frame: frame)
        let pixelBuffer = try makePixelBuffer(frame: frame)
        try copyPixels(from: frame, into: pixelBuffer)
        let formatDescription = try makeFormatDescription(pixelBuffer: pixelBuffer)
        let timing = makeTiming(presentationTime: frame.presentationTime)
        return try assembleSampleBuffer(
            pixelBuffer: pixelBuffer,
            formatDescription: formatDescription,
            timing: timing
        )
    }
}

private extension FrameSampleBufferAdapter {
    /// `copyPixels` の memcpy より前に dim / payload の整合性を確認する。
    /// `CVPixelBufferCreate` は負の dim を弾くものの、`bytesPerRow * height`
    /// の overflow や `pixelData` の short payload は CV では検出されないため
    /// out-of-bounds read で crash する。caller の validation に頼らず
    /// adapter 側で水際で止める ― IPC で渡ってきた値の信頼度は低い。
    static func validate(frame: Frame) throws {
        guard frame.width >= 0, frame.height >= 0, frame.bytesPerRow >= 0 else {
            throw FrameSampleBufferAdapterError.negativeDimension(
                width: frame.width,
                height: frame.height,
                bytesPerRow: frame.bytesPerRow
            )
        }
        let (required, overflowed) = frame.bytesPerRow.multipliedReportingOverflow(by: frame.height)
        guard !overflowed else {
            throw FrameSampleBufferAdapterError.requiredSizeOverflow(
                bytesPerRow: frame.bytesPerRow,
                height: frame.height
            )
        }
        guard frame.pixelData.count >= required else {
            throw FrameSampleBufferAdapterError.pixelDataTooShort(
                have: frame.pixelData.count,
                need: required
            )
        }
    }

    static func makePixelBuffer(frame: Frame) throws -> CVPixelBuffer {
        var buffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            frame.width,
            frame.height,
            frame.pixelFormat,
            // CMIO extension が拾える IOSurface-backed buffer にするには
            // `kCVPixelBufferIOSurfacePropertiesKey` を attribute dict に
            // 含める必要がある (中身は空 `[:]` でも有効 ― 同じパターンは
            // `LogoFrameRenderer` / `SampleBufferTranslatorTests` で先行採用済)。
            // key 自体を omit すると IOSurface 非サポートの CPU-only buffer
            // になり、client (Zoom 等) が rejects する。
            [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary,
            &buffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer = buffer else {
            throw FrameSampleBufferAdapterError.pixelBufferAllocFailed(code: Int(status))
        }
        return pixelBuffer
    }

    static func copyPixels(from frame: Frame, into pixelBuffer: CVPixelBuffer) throws {
        let lockResult = CVPixelBufferLockBaseAddress(pixelBuffer, [])
        guard lockResult == kCVReturnSuccess else {
            throw FrameSampleBufferAdapterError.pixelBufferLockFailed(code: Int(lockResult))
        }
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
            throw FrameSampleBufferAdapterError.pixelBufferBaseAddressMissing
        }
        let dstStride = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let rowBytes = min(frame.bytesPerRow, dstStride)
        let height = frame.height
        // GPU 要求の stride padding (CV が dst で広げる場合) があるため、
        // 連続 memcpy ではなく row 単位で写す。host 側 IOSurface の row
        // padding と同じ理屈 ― 詳細は IOSurfaceFactory.writeBytes 参照。
        frame.pixelData.withUnsafeBytes { raw in
            guard let src = raw.baseAddress else { return }
            (0..<height).forEach { row in
                let dst = base.advanced(by: row * dstStride)
                memcpy(dst, src.advanced(by: row * frame.bytesPerRow), rowBytes)
            }
        }
    }

    static func makeFormatDescription(pixelBuffer: CVPixelBuffer) throws -> CMFormatDescription {
        var formatDescription: CMFormatDescription?
        let status = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard status == noErr, let result = formatDescription else {
            throw FrameSampleBufferAdapterError.formatDescriptionFailed(code: Int(status))
        }
        return result
    }

    static func makeTiming(presentationTime: TimeInterval) -> CMSampleTimingInfo {
        // `.hostTime` clock + `CMTime(seconds:preferredTimescale:)` で
        // nanoseconds 基準に翻訳。timescale = `NSEC_PER_SEC` (= 1e9) なら
        // 30 fps × 数時間でも丸め誤差は 1 ns 未満で済む。
        let pts = CMTime(seconds: presentationTime, preferredTimescale: Int32(NSEC_PER_SEC))
        return CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
    }

    static func assembleSampleBuffer(
        pixelBuffer: CVPixelBuffer,
        formatDescription: CMFormatDescription,
        timing: CMSampleTimingInfo
    ) throws -> CMSampleBuffer {
        var sampleBuffer: CMSampleBuffer?
        var mutableTiming = timing
        let status = CMSampleBufferCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &mutableTiming,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let result = sampleBuffer else {
            throw FrameSampleBufferAdapterError.sampleBufferAssemblyFailed(code: Int(status))
        }
        return result
    }
}

public enum FrameSampleBufferAdapterError: Error, Equatable, Sendable {
    case negativeDimension(width: Int, height: Int, bytesPerRow: Int)
    case requiredSizeOverflow(bytesPerRow: Int, height: Int)
    case pixelDataTooShort(have: Int, need: Int)
    case pixelBufferAllocFailed(code: Int)
    case pixelBufferLockFailed(code: Int)
    case pixelBufferBaseAddressMissing
    case formatDescriptionFailed(code: Int)
    case sampleBufferAssemblyFailed(code: Int)
}
