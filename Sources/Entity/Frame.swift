import Foundation

/// A single video frame as pure data: raw pixel bytes plus the metadata
/// needed to reconstruct an `IOSurface` (or `CVPixelBuffer`) at any IPC
/// boundary.
///
/// Why pure data and not a direct `IOSurface` ref: Swift 6.3 strict
/// concurrency cannot transfer `IOSurface` references across actor
/// boundaries (see memory: `project-iosurface-actor-bug`), so Entity
/// stays a value type. The zero-copy benefit is realised at the IPC
/// boundary itself — `IOSurfaceFactory.make(...)` materialises an
/// `IOSurface` from `pixelData` just before crossing the Mach port.
public struct Frame: Sendable, Equatable {
    public let presentationTime: TimeInterval
    public let pixelData: Data
    public let width: Int
    public let height: Int
    public let pixelFormat: OSType
    public let bytesPerRow: Int

    public init(
        presentationTime: TimeInterval,
        pixelData: Data,
        width: Int,
        height: Int,
        pixelFormat: OSType,
        bytesPerRow: Int
    ) {
        self.presentationTime = presentationTime
        self.pixelData = pixelData
        self.width = width
        self.height = height
        self.pixelFormat = pixelFormat
        self.bytesPerRow = bytesPerRow
    }
}
