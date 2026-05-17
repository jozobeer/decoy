import CoreGraphics
import CoreMedia
import CoreText
import CoreVideo
import Foundation

/// extension が送出する固定パターン frame の生成器。
///
/// Decoy ブランドの teal 背景 (`#06b6d4`) に白い "DECOY" テキスト。動かない
/// 静止画でいい ― 「Decoy が動いている」ことが Zoom などで識別できれば
/// 本 issue の目的 (extension が frame を流せる) を満たす。
final class LogoFrameRenderer {
    private let width: Int
    private let height: Int
    private let pixelBufferPool: CVPixelBufferPool
    private let cachedImage: CGImage

    init(width: Int, height: Int) {
        self.width = width
        self.height = height

        let poolAttributes: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 3]
        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height,
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:],
        ]
        var pool: CVPixelBufferPool?
        CVPixelBufferPoolCreate(nil, poolAttributes as CFDictionary, pixelBufferAttributes as CFDictionary, &pool)
        guard let pool else { fatalError("Failed to create CVPixelBufferPool") }
        pixelBufferPool = pool

        cachedImage = LogoFrameRenderer.renderLogo(width: width, height: height)
    }

    func nextFrame() -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pixelBufferPool, &pixelBuffer)
        guard let pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return nil }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.draw(cachedImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        return pixelBuffer
    }
}

extension LogoFrameRenderer {
    static func formatDescription(width: Int, height: Int) -> CMFormatDescription {
        var description: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: nil,
            codecType: kCVPixelFormatType_32BGRA,
            width: Int32(width),
            height: Int32(height),
            extensions: nil,
            formatDescriptionOut: &description
        )
        guard let description else { fatalError("Failed to create CMFormatDescription") }
        return description
    }

    static func sampleBuffer(from pixelBuffer: CVPixelBuffer) -> CMSampleBuffer? {
        var formatDescription: CMFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard let formatDescription else { return nil }

        let now = CMClockGetTime(CMClockGetHostTimeClock())
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 30),
            presentationTimeStamp: now,
            decodeTimeStamp: .invalid
        )

        var sampleBuffer: CMSampleBuffer?
        CMSampleBufferCreateForImageBuffer(
            allocator: nil,
            imageBuffer: pixelBuffer,
            dataReady: true,
            makeDataReadyCallback: nil,
            refcon: nil,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        return sampleBuffer
    }

    private static func renderLogo(width: Int, height: Int) -> CGImage {
        let canvasSize = CGSize(width: width, height: height)
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        )!
        // Decoy theme color (#06b6d4 ― tailwind cyan-500)
        context.setFillColor(red: 6 / 255, green: 182 / 255, blue: 212 / 255, alpha: 1)
        context.fill(CGRect(origin: .zero, size: canvasSize))

        let font = CTFontCreateWithName("HelveticaNeue-Bold" as CFString, CGFloat(height) / 4, nil)
        let textColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
        let attributes: [CFString: Any] = [
            kCTFontAttributeName: font,
            kCTForegroundColorAttributeName: textColor,
        ]
        let attributed = CFAttributedStringCreate(nil, "DECOY" as CFString, attributes as CFDictionary)!
        let line = CTLineCreateWithAttributedString(attributed)
        let bounds = CTLineGetImageBounds(line, context)
        let originX = (CGFloat(width) - bounds.width) / 2 - bounds.minX
        let originY = (CGFloat(height) - bounds.height) / 2 - bounds.minY
        context.textPosition = CGPoint(x: originX, y: originY)
        CTLineDraw(line, context)

        guard let image = context.makeImage() else { fatalError("Failed to render logo image") }
        return image
    }
}
