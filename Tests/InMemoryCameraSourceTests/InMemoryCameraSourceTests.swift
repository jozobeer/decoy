import Testing
import Foundation
import Domain
@testable import InMemoryCameraSource

@Suite("InMemoryCameraSource")
struct InMemoryCameraSourceTests {
    private func makeFrame(t: TimeInterval = 0, label: String = "") -> Frame {
        Frame(presentationTime: t, data: Data(label.utf8))
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

    @Test func singleFrame_streamEmitsThatFrame() async {
        let f = makeFrame(t: 1, label: "a")
        let source = InMemoryCameraSource(emitting: [f])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected == [f])
    }

    @Test func multipleFrames_preservesOrder() async {
        let f1 = makeFrame(t: 1, label: "a")
        let f2 = makeFrame(t: 2, label: "b")
        let f3 = makeFrame(t: 3, label: "c")
        let source = InMemoryCameraSource(emitting: [f1, f2, f3])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected == [f1, f2, f3])
    }

    @Test func framesCalled_incrementsSubscribeCount() async {
        let source = InMemoryCameraSource(emitting: [makeFrame(label: "a")])
        _ = await source.frames()
        let after1 = await source.subscribeCount
        #expect(after1 == 1)
        _ = await source.frames()
        let after2 = await source.subscribeCount
        #expect(after2 == 2)
    }

    @Test func multipleSubscribers_eachReceiveFullPreset() async {
        let f1 = makeFrame(t: 1, label: "a")
        let f2 = makeFrame(t: 2, label: "b")
        let source = InMemoryCameraSource(emitting: [f1, f2])
        let stream1 = await source.frames()
        let stream2 = await source.frames()
        let c1 = await collect(stream1)
        let c2 = await collect(stream2)
        #expect(c1 == [f1, f2])
        #expect(c2 == [f1, f2])
    }

    @Test func duplicatePresetFrames_emitsBothCopies() async {
        let f = makeFrame(t: 1, label: "a")
        let source = InMemoryCameraSource(emitting: [f, f])
        let stream = await source.frames()
        let collected = await collect(stream)
        #expect(collected == [f, f])
    }
}
