import Testing
import Foundation
import CoreMedia
import CoreVideo
import Domain
@testable import AVCameraSource

@Suite("SampleBufferTranslator")
struct SampleBufferTranslatorTests {
    /// Build a synthetic BGRA `CMSampleBuffer` carrying an IOSurface-backed
    /// `CVPixelBuffer`. The translator's contract is "extract the
    /// IOSurface and presentation time" — it does not transform pixel
    /// content — so fixtures only need to be IOSurface-backed.
    private func makeSampleBuffer(
        width: Int,
        height: Int,
        presentationSeconds: Double
    ) throws -> CMSampleBuffer {
        let pixelBuffer = try makePixelBuffer(width: width, height: height)
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

    private func makePixelBuffer(width: Int, height: Int) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let attrs: CFDictionary = [
            kCVPixelBufferIOSurfacePropertiesKey: [:] as CFDictionary,
        ] as CFDictionary
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            kCVPixelFormatType_32BGRA,
            attrs,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw TestError.pixelBufferCreationFailed(status)
        }
        return pixelBuffer
    }

    enum TestError: Error {
        case pixelBufferCreationFailed(CVReturn)
        case sampleBufferCreationFailed(OSStatus)
        case formatDescriptionCreationFailed(OSStatus)
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
        let buffer = try makeSampleBuffer(width: 4, height: 4, presentationSeconds: pts)
        let translated = frame(from: buffer)
        #expect(translated != nil)
        #expect(abs((translated?.presentationTime ?? 0) - pts) < 0.0001)
    }

    @Test("frame(from:) extracts pixel data + dims + format from the CVPixelBuffer")
    func translatorExtractsPixelMetadata() throws {
        let buffer = try makeSampleBuffer(width: 8, height: 4, presentationSeconds: 0)
        let translated = try #require(frame(from: buffer))
        #expect(translated.width == 8)
        #expect(translated.height == 4)
        #expect(translated.pixelFormat == kCVPixelFormatType_32BGRA)
        #expect(translated.pixelData.count == translated.bytesPerRow * translated.height)
    }
}
