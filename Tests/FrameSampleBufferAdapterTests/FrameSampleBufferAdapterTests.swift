import CoreMedia
import CoreVideo
import Domain
import Foundation
import Testing
@testable import FrameSampleBufferAdapter

@Suite("FrameSampleBufferAdapter")
struct FrameSampleBufferAdapterTests {
    @Test("sampleBuffer round-trips Frame metadata into CMSampleBuffer")
    func sampleBuffer_roundTripsMetadata() throws {
        let width = 4
        let height = 4
        let bytesPerRow = width * 4
        let payload = Data((0..<(bytesPerRow * height)).map { UInt8($0 & 0xFF) })
        let frame = Frame(
            presentationTime: 1.5,
            pixelData: payload,
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: bytesPerRow
        )

        let sampleBuffer = try FrameSampleBufferAdapter.sampleBuffer(from: frame)

        let imageBuffer = try #require(CMSampleBufferGetImageBuffer(sampleBuffer))
        #expect(CVPixelBufferGetWidth(imageBuffer) == width)
        #expect(CVPixelBufferGetHeight(imageBuffer) == height)
        #expect(CVPixelBufferGetPixelFormatType(imageBuffer) == kCVPixelFormatType_32BGRA)

        let pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        // 1.5 s が CMTime(value: NSEC_PER_SEC * 3 / 2, timescale: NSEC_PER_SEC)
        // で表現できる ― rounding 誤差ゼロ。
        #expect(CMTimeGetSeconds(pts) == 1.5)
    }

    @Test("sampleBuffer copies pixel bytes into the CVPixelBuffer (BGRA path)")
    func sampleBuffer_copiesPixelBytes() throws {
        let width = 4
        let height = 4
        let bytesPerRow = width * 4
        let payload = Data((0..<(bytesPerRow * height)).map { UInt8($0 & 0xFF) })
        let frame = Frame(
            presentationTime: 0.0,
            pixelData: payload,
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: bytesPerRow
        )

        let sampleBuffer = try FrameSampleBufferAdapter.sampleBuffer(from: frame)
        let imageBuffer = try #require(CMSampleBufferGetImageBuffer(sampleBuffer))

        let lockResult = CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        #expect(lockResult == kCVReturnSuccess)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let dstStride = CVPixelBufferGetBytesPerRow(imageBuffer)
        let base = try #require(CVPixelBufferGetBaseAddress(imageBuffer))
        // GPU 用に dstStride は元の bytesPerRow 以上に丸められ得るので、
        // row 単位で読み戻して元 payload と比較する。
        let rowBytes = min(bytesPerRow, dstStride)
        (0..<height).forEach { row in
            let src = base.advanced(by: row * dstStride)
            let readBack = Data(bytes: src, count: rowBytes)
            let expected = payload.subdata(in: (row * bytesPerRow)..<(row * bytesPerRow + rowBytes))
            #expect(readBack == expected)
        }
    }

    @Test("sampleBuffer rejects negative dimensions with a typed error")
    func sampleBuffer_rejectsNegativeDim() {
        let frame = Frame(
            presentationTime: 0.0,
            pixelData: Data(repeating: 0, count: 16),
            width: -1,
            height: 4,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: 4
        )
        #expect(throws: FrameSampleBufferAdapterError.negativeDimension(width: -1, height: 4, bytesPerRow: 4)) {
            try FrameSampleBufferAdapter.sampleBuffer(from: frame)
        }
    }

    @Test("sampleBuffer rejects pixelData shorter than bytesPerRow * height")
    func sampleBuffer_rejectsShortPixelData() {
        let width = 4
        let height = 4
        let bytesPerRow = width * 4
        // need = 64, have = 16
        let frame = Frame(
            presentationTime: 0.0,
            pixelData: Data(repeating: 0, count: 16),
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: bytesPerRow
        )
        #expect(throws: FrameSampleBufferAdapterError.pixelDataTooShort(have: 16, need: 64)) {
            try FrameSampleBufferAdapter.sampleBuffer(from: frame)
        }
    }

    @Test("sampleBuffer rejects bytesPerRow * height overflow")
    func sampleBuffer_rejectsOverflow() {
        // bytesPerRow = Int.max, height = 2 → overflow
        let frame = Frame(
            presentationTime: 0.0,
            pixelData: Data(),
            width: 1,
            height: 2,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: Int.max
        )
        #expect(throws: FrameSampleBufferAdapterError.requiredSizeOverflow(bytesPerRow: Int.max, height: 2)) {
            try FrameSampleBufferAdapter.sampleBuffer(from: frame)
        }
    }

    @Test("sampleBuffer carries CMVideoFormatDescription with matching dims")
    func sampleBuffer_carriesFormatDescription() throws {
        let width = 8
        let height = 4
        let bytesPerRow = width * 4
        let frame = Frame(
            presentationTime: 0.0,
            pixelData: Data(repeating: 0xAA, count: bytesPerRow * height),
            width: width,
            height: height,
            pixelFormat: kCVPixelFormatType_32BGRA,
            bytesPerRow: bytesPerRow
        )

        let sampleBuffer = try FrameSampleBufferAdapter.sampleBuffer(from: frame)
        let formatDescription = try #require(CMSampleBufferGetFormatDescription(sampleBuffer))
        let dims = CMVideoFormatDescriptionGetDimensions(formatDescription)
        #expect(Int(dims.width) == width)
        #expect(Int(dims.height) == height)
    }
}
