import Testing
import Foundation
import CoreMedia
import CoreVideo
import Domain
@testable import AVCameraSource

@Suite("SampleBufferTranslator")
struct SampleBufferTranslatorTests {
    /// Build a synthetic NV12 (`420YpCbCr8BiPlanarVideoRange`) CMSampleBuffer
    /// from a Y plane and a CbCr plane.
    private func makeSampleBuffer(
        width: Int,
        height: Int,
        yBytes: [UInt8],
        cbCrBytes: [UInt8],
        presentationSeconds: Double
    ) throws -> CMSampleBuffer {
        let pixelBuffer = try makePixelBuffer(
            width: width,
            height: height,
            yBytes: yBytes,
            cbCrBytes: cbCrBytes
        )
        let pts = CMTime(seconds: presentationSeconds, preferredTimescale: 1_000_000)
        var formatDesc: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDesc
        )
        guard formatStatus == noErr, let formatDesc else {
            throw TestError.formatDescriptionCreationFailed(formatStatus)
        }
        var timing = CMSampleTimingInfo(
            duration: .invalid,
            presentationTimeStamp: pts,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDesc,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard status == noErr, let sampleBuffer else {
            throw TestError.sampleBufferCreationFailed(status)
        }
        return sampleBuffer
    }

    private func makePixelBuffer(
        width: Int,
        height: Int,
        yBytes: [UInt8],
        cbCrBytes: [UInt8]
    ) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange,
            attrs,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw TestError.pixelBufferCreationFailed(status)
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }
        try writePlane(
            pixelBuffer: pixelBuffer,
            planeIndex: 0,
            bytes: yBytes,
            expectedRows: height
        )
        try writePlane(
            pixelBuffer: pixelBuffer,
            planeIndex: 1,
            bytes: cbCrBytes,
            expectedRows: height / 2
        )
        return pixelBuffer
    }

    private func writePlane(
        pixelBuffer: CVPixelBuffer,
        planeIndex: Int,
        bytes: [UInt8],
        expectedRows: Int
    ) throws {
        guard let base = CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, planeIndex) else {
            throw TestError.planeBaseAddressMissing(planeIndex)
        }
        let rowBytes = CVPixelBufferGetBytesPerRowOfPlane(pixelBuffer, planeIndex)
        let widthBytes = CVPixelBufferGetWidthOfPlane(pixelBuffer, planeIndex)
            * (planeIndex == 0 ? 1 : 2) // CbCr is interleaved 2 bytes per chroma sample
        // initialize the entire allocation to a known value so unwritten
        // padding is deterministic
        memset(base, 0, rowBytes * expectedRows)
        bytes.withUnsafeBufferPointer { src in
            (0..<expectedRows).forEach { row in
                let rowSrcOffset = row * widthBytes
                guard rowSrcOffset < src.count else { return }
                let bytesToCopy = min(widthBytes, src.count - rowSrcOffset)
                let dst = base.advanced(by: row * rowBytes)
                memcpy(dst, src.baseAddress?.advanced(by: rowSrcOffset), bytesToCopy)
            }
        }
    }

    enum TestError: Error {
        case pixelBufferCreationFailed(CVReturn)
        case sampleBufferCreationFailed(OSStatus)
        case formatDescriptionCreationFailed(OSStatus)
        case planeBaseAddressMissing(Int)
    }

    @Test("frame(from:) returns nil when sample buffer carries no image buffer")
    func translatorReturnsNilForBufferWithoutImage() throws {
        // CMSampleBufferCreate without an image buffer = no image to read
        var sampleBuffer: CMSampleBuffer?
        let status = CMSampleBufferCreate(
            allocator: kCFAllocatorDefault,
            dataBuffer: nil,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: nil,
            sampleCount: 0,
            sampleTimingEntryCount: 0,
            sampleTimingArray: nil,
            sampleSizeEntryCount: 0,
            sampleSizeArray: nil,
            sampleBufferOut: &sampleBuffer
        )
        #expect(status == noErr)
        let buffer = try #require(sampleBuffer)
        #expect(frame(from: buffer) == nil)
    }

    @Test("frame(from:) preserves presentation time in seconds")
    func translatorPreservesPresentationTime() throws {
        let pts = 1.5
        let buffer = try makeSampleBuffer(
            width: 2,
            height: 2,
            yBytes: [0, 0, 0, 0],
            cbCrBytes: [0, 0],
            presentationSeconds: pts
        )
        let translated = frame(from: buffer)
        #expect(translated != nil)
        #expect(abs((translated?.presentationTime ?? 0) - pts) < 0.0001)
    }

    @Test("frame(from:) concatenates Y plane followed by CbCr plane bytes")
    func translatorConcatenatesPlanes() throws {
        // 2x2 image: Y plane = 4 bytes, CbCr plane = 2 bytes (one pair)
        let y: [UInt8] = [0x11, 0x22, 0x33, 0x44]
        let cbcr: [UInt8] = [0x55, 0x66]
        let buffer = try makeSampleBuffer(
            width: 2,
            height: 2,
            yBytes: y,
            cbCrBytes: cbcr,
            presentationSeconds: 0
        )
        let translated = frame(from: buffer)
        #expect(translated != nil)
        // expected layout: Y bytes, then CbCr bytes
        let expected = Data(y + cbcr)
        #expect(translated?.data == expected)
    }
}
