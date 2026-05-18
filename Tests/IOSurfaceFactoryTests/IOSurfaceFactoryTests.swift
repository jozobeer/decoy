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

        let readBack = IOSurfaceFactory.readBytes(surface)
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
        let width = 2
        let height = 2
        let initial = Data([0x10, 0x20, 0x30, 0x40, 0x50, 0x60, 0x70, 0x80,
                            0x90, 0xA0, 0xB0, 0xC0, 0xD0, 0xE0, 0xF0, 0x00])
        let surface = try IOSurfaceFactory.makeBGRA(width: width, height: height, bytes: initial)

        var firstRead = IOSurfaceFactory.readBytes(surface)
        firstRead[0] = 0xFF

        let secondRead = IOSurfaceFactory.readBytes(surface)
        #expect(secondRead.first == 0x10)
    }
}
