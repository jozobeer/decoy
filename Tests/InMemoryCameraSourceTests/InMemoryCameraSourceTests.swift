import Testing
import Foundation
import Domain
@testable import InMemoryCameraSource

@Suite("InMemoryCameraSource")
struct InMemoryCameraSourceTests {
    private func makeFrame(t: TimeInterval = 0, payload: UInt8 = 0) -> Frame {
        Frame(presentationTime: t, pixelData: Data(repeating: payload, count: 64), width: 4, height: 4, pixelFormat: 0x42475241, bytesPerRow: 16)
    }

    private func collect(_ stream: AsyncStream<Frame>) async -> [Frame] {
        await stream.reduce(into: [Frame]()) { $0.append($1) }
    }

    @Test func emptyInit_subscribeCountIsZero() async {
        let source = InMemoryCameraSource()
        let count = await source.subscribeCount
        #expect(count == 0)
    }

    @Test func emptyEmitting_streamFinishesImmediately() async {
        let source = InMemoryCameraSource(emitting: [])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected.isEmpty)
    }

    @Test func singleFrame_streamEmitsThatFrame() async throws {
        let f = makeFrame(t: 1, payload: 0xA1)
        let source = InMemoryCameraSource(emitting: [f])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected == [f])
    }

    @Test func multipleFrames_preservesOrder() async throws {
        let f1 = makeFrame(t: 1, payload: 0xA1)
        let f2 = makeFrame(t: 2, payload: 0xB2)
        let f3 = makeFrame(t: 3, payload: 0xC3)
        let source = InMemoryCameraSource(emitting: [f1, f2, f3])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected == [f1, f2, f3])
    }

    @Test func framesCalled_incrementsSubscribeCount() async throws {
        let source = InMemoryCameraSource(emitting: [makeFrame(payload: 0xA1)])
        _ = await source.frames()
        let after1 = await source.subscribeCount
        #expect(after1 == 1)
        _ = await source.frames()
        let after2 = await source.subscribeCount
        #expect(after2 == 2)
    }

    @Test func multipleSubscribers_eachReceiveFullPreset() async throws {
        let f1 = makeFrame(t: 1, payload: 0xA1)
        let f2 = makeFrame(t: 2, payload: 0xB2)
        let source = InMemoryCameraSource(emitting: [f1, f2])
        let stream1 = await source.frames()
        let stream2 = await source.frames()
        let c1 = await collect(stream1)
        let c2 = await collect(stream2)
        #expect(c1 == [f1, f2])
        #expect(c2 == [f1, f2])
    }

    @Test func duplicatePresetFrames_emitsBothCopies() async throws {
        let f = makeFrame(t: 1, payload: 0xA1)
        let source = InMemoryCameraSource(emitting: [f, f])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected == [f, f])
    }
}
