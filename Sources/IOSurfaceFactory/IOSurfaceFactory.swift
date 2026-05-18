import Foundation
@preconcurrency import IOSurface

/// Helpers for constructing `IOSurface` instances from raw pixel data and
/// for reading the raw backing bytes back out.
///
/// `Frame` (Entity) carries pixel bytes as `Data` because Swift 6.3 cannot
/// transfer `IOSurface` refs across actor boundaries (memory
/// `project-iosurface-actor-bug`). Zero-copy is realised here: at the
/// IPC boundary the host side materialises an `IOSurface` from
/// `Frame.pixelData` via `make(...)` and ships only the surface ref
/// across the Mach port; the camera-extension side reads bytes back via
/// `readBytes(...)`.
public enum IOSurfaceFactory {}

extension IOSurfaceFactory {
    /// Allocate a fresh `IOSurface` with the given dimensions and pixel
    /// format, then copy `bytes` into its base address.
    ///
    /// `bytesPerRow` is required because callers know it (it can differ
    /// from `width * bytesPerElement` for aligned formats) and `IOSurface`
    /// won't infer it. `bytes.count` must be at least `bytesPerRow *
    /// height`; extra bytes are ignored.
    public static func make(
        width: Int,
        height: Int,
        pixelFormat: OSType,
        bytesPerElement: Int,
        bytesPerRow: Int,
        bytes: Data
    ) throws -> IOSurface {
        let allocSize = bytesPerRow * height
        guard bytes.count >= allocSize else {
            throw IOSurfaceFactoryError.bytesTooShort(have: bytes.count, need: allocSize)
        }
        let properties: [IOSurfacePropertyKey: Any] = [
            .width: width,
            .height: height,
            .bytesPerElement: bytesPerElement,
            .bytesPerRow: bytesPerRow,
            .pixelFormat: Int(pixelFormat),
            .allocSize: allocSize,
        ]
        guard let surface = Self.allocateSurface(properties: properties) else {
            throw IOSurfaceFactoryError.allocationFailed
        }
        try writeBytes(bytes, into: surface, count: allocSize)
        return surface
    }

    /// BGRA 8-bit-per-channel convenience: `bytesPerElement = 4`,
    /// `bytesPerRow = width * 4`, `pixelFormat =
    /// kCVPixelFormatType_32BGRA`.
    public static func makeBGRA(width: Int, height: Int, bytes: Data) throws -> IOSurface {
        try make(
            width: width,
            height: height,
            pixelFormat: 0x42475241, // 'BGRA' — kCVPixelFormatType_32BGRA without importing CoreVideo
            bytesPerElement: 4,
            bytesPerRow: width * 4,
            bytes: bytes
        )
    }

    /// Read the entire backing buffer of `surface` as `Data`.
    ///
    /// Acquires a read lock for the duration of the copy. The returned
    /// `Data` is an independent heap copy; subsequent mutations of the
    /// surface do not affect it.
    public static func readBytes(_ surface: IOSurface) -> Data {
        var seed: UInt32 = 0
        _ = surface.lock(options: .readOnly, seed: &seed)
        defer { _ = surface.unlock(options: .readOnly, seed: &seed) }
        return Data(bytes: surface.baseAddress, count: surface.allocationSize)
    }
}

private extension IOSurfaceFactory {
    /// `IOSurface.init(properties:)` types its dict value as `Any`,
    /// which Swift 6 strict concurrency cannot prove `Sendable`. Our
    /// only caller passes a dict whose values are all `Int` (all
    /// `Sendable`), so dropping to the C API `IOSurfaceCreate` —
    /// which takes `CFDictionary`, sidestepping the `Any` typing
    /// problem entirely — avoids the warning without weakening the
    /// rest of the file's strict-concurrency checking.
    static func allocateSurface(properties: [IOSurfacePropertyKey: Any]) -> IOSurface? {
        let cfDict = properties as CFDictionary
        guard let ref = IOSurfaceCreate(cfDict) else { return nil }
        return ref as IOSurface
    }

    static func writeBytes(_ bytes: Data, into surface: IOSurface, count: Int) throws {
        var seed: UInt32 = 0
        let lockResult = surface.lock(options: [], seed: &seed)
        guard lockResult == kIOReturnSuccess else {
            throw IOSurfaceFactoryError.lockFailed(code: Int(lockResult))
        }
        defer { _ = surface.unlock(options: [], seed: &seed) }
        bytes.withUnsafeBytes { raw in
            guard let src = raw.baseAddress else { return }
            memcpy(surface.baseAddress, src, count)
        }
    }
}

public enum IOSurfaceFactoryError: Error, Sendable, Equatable {
    case allocationFailed
    case bytesTooShort(have: Int, need: Int)
    case lockFailed(code: Int)
}

extension IOSurfaceFactory {
    /// Test convenience: build a 4×4 BGRA `IOSurface` (64 bytes,
    /// hardware-aligned) whose every byte is `payload`. Useful for
    /// cheap test fixtures where the exact pixel content does not
    /// matter and only frame identity / presentation time is being
    /// asserted.
    ///
    /// Why 4×4 rather than 1×1: macOS `IOSurface` rejects or silently
    /// rounds up sub-16-byte `bytesPerRow` requests because GPU access
    /// requires a minimum alignment. Using `width = 4` (= 16 B/row)
    /// stays comfortably above that and yields a fully populated 64 B
    /// allocation so `readBytes` round-trips cleanly.
    public static func unitBGRA(payload: UInt8) throws -> IOSurface {
        try makeBGRA(width: 4, height: 4, bytes: Data(repeating: payload, count: 64))
    }
}
