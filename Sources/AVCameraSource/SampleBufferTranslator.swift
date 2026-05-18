import Foundation
import CoreMedia
import CoreVideo
import Domain

/// Translates a `CMSampleBuffer` delivered by AVFoundation into a
/// pure-data `Frame` (raw pixel bytes + dims + format).
///
/// AVFoundation hands us a `CVPixelBuffer` backed by `IOSurface`; we
/// lock its base address, copy the bytes into a `Data`, and let
/// AVFoundation reclaim the pixel buffer after the callback. The copy
/// is the price of keeping `Frame` actor-transferable in Swift 6.3 —
/// see memory `project-iosurface-actor-bug`. The zero-copy benefit is
/// restored at the Mach-port IPC boundary (PR 2), where the bytes are
/// re-materialised into a fresh `IOSurface` for the Camera Extension.
///
/// Returns `nil` when the sample buffer carries no image (metadata-only
/// buffers), the PTS is non-finite, or the base address cannot be
/// locked.
func frame(from sampleBuffer: CMSampleBuffer) -> Frame? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return nil
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    guard pts.isFinite else { return nil }
    guard CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly) == kCVReturnSuccess else {
        return nil
    }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
    let height = CVPixelBufferGetHeight(pixelBuffer)
    let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
    return Frame(
        presentationTime: pts,
        pixelData: Data(bytes: base, count: bytesPerRow * height),
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: height,
        pixelFormat: CVPixelBufferGetPixelFormatType(pixelBuffer),
        bytesPerRow: bytesPerRow
    )
}
