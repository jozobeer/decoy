import Testing
import Foundation
import Domain
@testable import InMemoryVirtualCameraSink

@Suite("InMemoryVirtualCameraSink")
struct InMemoryVirtualCameraSinkTests {
    private func makeFrame(t: TimeInterval = 0, label: String = "") -> Frame {
        Frame(presentationTime: t, data: Data(label.utf8))
    }

    @Test func emptyInit_framesIsEmpty() async {
        let sink = InMemoryVirtualCameraSink()
        let frames = await sink.frames
        #expect(frames.isEmpty)
    }

    @Test func send_oneFrame_framesContainsThatFrame() async throws {
        let sink = InMemoryVirtualCameraSink()
        let f = makeFrame(t: 1, label: "a")
        try await sink.send(f)
        let frames = await sink.frames
        #expect(frames == [f])
    }

    @Test func send_multipleFrames_preservesOrder() async throws {
        let sink = InMemoryVirtualCameraSink()
        let f1 = makeFrame(t: 1, label: "a")
        let f2 = makeFrame(t: 2, label: "b")
        let f3 = makeFrame(t: 3, label: "c")
        try await sink.send(f1)
        try await sink.send(f2)
        try await sink.send(f3)
        let frames = await sink.frames
        #expect(frames == [f1, f2, f3])
    }

    @Test func send_sameFrameTwice_appendsBothCopies() async throws {
        let sink = InMemoryVirtualCameraSink()
        let f = makeFrame(t: 1, label: "a")
        try await sink.send(f)
        try await sink.send(f)
        let frames = await sink.frames
        #expect(frames == [f, f])
    }
}
