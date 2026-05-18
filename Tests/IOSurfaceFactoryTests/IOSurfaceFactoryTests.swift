import Foundation
import IOSurface
import Testing
@testable import IOSurfaceFactory

@Suite("IOSurfaceFactory")
struct IOSurfaceFactoryTests {
    @Test("makeBGRA round-trips raw bytes")
    func makeBGRA_roundTripsBytes() throws {
        let width = 4
        let height = 2
        let pixels = Data((0..<(width * height * 4)).map { UInt8($0 & 0xFF) })

        let surface = try IOSurfaceFactory.makeBGRA(width: width, height: height, bytes: pixels)

        #expect(surface.width == width)
        #expect(surface.height == height)
        #expect(surface.bytesPerRow == width * 4)

        let readBack = try IOSurfaceFactory.readBytes(surface)
        #expect(readBack.prefix(pixels.count) == pixels)
    }

    @Test("make rejects bytes shorter than required allocation")
    func make_rejectsShortBytes() {
        let width = 4
        let height = 2
        let tooShort = Data(repeating: 0, count: 4)
        #expect(throws: IOSurfaceFactoryError.bytesTooShort(have: 4, need: width * height * 4)) {
            try IOSurfaceFactory.makeBGRA(width: width, height: height, bytes: tooShort)
        }
    }

    @Test("readBytes returns an independent copy")
    func readBytes_returnsIndependentCopy() throws {
        // 4×2 keeps `bytesPerRow = 16` ≥ macOS IOSurface's GPU-alignment
        // floor; a 2×2 surface (`bytesPerRow = 8`) is in the zone where
        // the kernel may reject the allocation or silently round the
        // stride, making the test flake on stride-padded paths.
        let width = 4
        let height = 2
        let initial = Data((0..<(width * height * 4)).map { UInt8($0 & 0xFF) })
        let surface = try IOSurfaceFactory.makeBGRA(width: width, height: height, bytes: initial)

        var firstRead = try IOSurfaceFactory.readBytes(surface)
        firstRead[0] = 0xFF

        let secondRead = try IOSurfaceFactory.readBytes(surface)
        #expect(secondRead.first == initial.first)
    }

    @Test("make rejects negative dimensions")
    func make_rejectsNegativeDimensions() {
        let bytes = Data(repeating: 0, count: 64)
        #expect(throws: IOSurfaceFactoryError.self) {
            try IOSurfaceFactory.make(
                width: -1,
                height: 1,
                pixelFormat: 0x42475241,
                bytesPerElement: 4,
                bytesPerRow: 4,
                bytes: bytes
            )
        }
        #expect(throws: IOSurfaceFactoryError.self) {
            try IOSurfaceFactory.make(
                width: 1,
                height: -1,
                pixelFormat: 0x42475241,
                bytesPerElement: 4,
                bytesPerRow: 4,
                bytes: bytes
            )
        }
    }

    @Test("make rejects allocSize overflow")
    func make_rejectsAllocSizeOverflow() {
        let bytes = Data(repeating: 0, count: 64)
        #expect(throws: IOSurfaceFactoryError.self) {
            try IOSurfaceFactory.make(
                width: 1,
                height: Int.max,
                pixelFormat: 0x42475241,
                bytesPerElement: 4,
                bytesPerRow: Int.max,
                bytes: bytes
            )
        }
    }

    @Test("makeBGRA rejects width that overflows bytesPerRow")
    func makeBGRA_rejectsBytesPerRowOverflow() {
        let bytes = Data(repeating: 0, count: 64)
        #expect(throws: IOSurfaceFactoryError.self) {
            try IOSurfaceFactory.makeBGRA(width: Int.max, height: 1, bytes: bytes)
        }
    }

    @Test("writeBytes honours surface-resolved row stride")
    func writeBytes_usesResolvedStride() throws {
        // 4×2 BGRA: bytesPerRow=16 is already 16-byte aligned so the
        // surface keeps it intact and a full round-trip is byte-exact.
        // This guards against accidental contiguous memcpy of
        // `bytesPerRow*height` bytes — the surface's resolved
        // `bytesPerRow` is what writeBytes must walk over per row.
        let width = 4
        let height = 2
        // distinct value per row so a row-shift would be detectable
        let row0 = Data(repeating: 0xAA, count: width * 4)
        let row1 = Data(repeating: 0xBB, count: width * 4)
        let surface = try IOSurfaceFactory.makeBGRA(width: width, height: height, bytes: row0 + row1)

        let bytesPerRow = surface.bytesPerRow
        let readBack = try IOSurfaceFactory.readBytes(surface)
        // row 0 starts at offset 0
        #expect(readBack[0] == 0xAA)
        // row 1 starts at offset bytesPerRow, not at offset (width*4) —
        // they coincide only when the kernel preserves the requested stride
        #expect(readBack[bytesPerRow] == 0xBB)
    }
}
