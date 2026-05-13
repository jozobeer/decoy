import Foundation
import CoreMedia
import CoreVideo
import Domain

/// Translates a NV12 `CMSampleBuffer` (delivered by AVFoundation) into
/// a `Frame`.
///
/// The output `Frame.data` layout is the Y plane bytes followed by the
/// interleaved CbCr plane bytes — both planes copied with their tight
/// per-row width (row padding stripped). Downstream consumers
/// (`Recorder`, `VirtualCameraSink`) treat `data` as opaque, so the
/// only contract is "round-trippable bytes with deterministic layout".
///
/// Returns `nil` when the sample buffer does not carry an image (e.g.,
/// metadata-only buffers) — callers should ignore such buffers.
func frame(from sampleBuffer: CMSampleBuffer) -> Frame? {
    guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
        return nil
    }
    let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
    guard pts.isFinite else { return nil }
    guard let bytes = bytesFromPixelBuffer(pixelBuffer) else { return nil }
    return Frame(presentationTime: pts, data: bytes)
}

/// Copy a bi-planar NV12 pixel buffer into a tight `Data` blob.
///
/// Layout: `[Y plane (width*height bytes)][CbCr plane (width*height/2 bytes)]`.
/// Row padding (stride > width) is stripped so the output is canonical.
private func bytesFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> Data? {
    let lock = CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
    guard lock == kCVReturnSuccess else { return nil }
    defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly) }

    let planeCount = CVPixelBufferGetPlaneCount(pixelBuffer)
    guard planeCount == 2 else { return nil }

    let yPlane = packedPlane(pixelBuffer: pixelBuffer, planeIndex: 0, bytesPerPixel: 1)
    let cbCrPlane = packedPlane(pixelBuffer: pixelBuffer, planeIndex: 1, bytesPerPixel: 2)
    guard let yPlane, let cbCrPlane else { return nil }
    return yPlane + cbCrPlane
}

/// Copy one plane into a tight `Data` (no row padding). Returns `nil`
/// if the plane's base address is missing.
///
/// - parameter bytesPerPixel: how many bytes of "data" exist per
///   horizontal pixel on this plane. Y plane = 1, CbCr plane = 2
///   (interleaved Cb,Cr samples).
private func packedPlane(
    pixelBuffer: CVPixelBuffer,
    planeIndex: Int,
    bytesPerPixel: Int
) -> Data? {
    guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex) else {
        return nil
    }
    let rows = CVPixelBufferGetHeightOfPlane(pixelBuffer, planeIndex)
    let width = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
    let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
    let widthBytes = width * bytesPerPixel
    return (0..<rows).reduce(into: Data(capacity: rows * widthBytes)) { acc, row in
        let rowPtr = base.advanced(by: row * rowBytes)
        acc.append(Data(bytes: rowPtr, count: widthBytes))
    }
}
