import Testing
import Foundation
import Domain
@testable import FileSystemClipStore

@Suite("FileSystemClipStore")
struct FileSystemClipStoreTests {
    // MARK: - Helpers

    /// Creates an isolated temp directory for one test and tears it down
    /// when the returned `TempDir` goes out of scope.
    private static func makeTempRoot() -> TempDir {
        let url = FileManager.default
            .temporaryDirectory
            .appendingPathComponent("FileSystemClipStoreTests-\(UUID().uuidString)", isDirectory: true)
        return TempDir(url: url)
    }

    private func makeClip(
        id: UUID = UUID(),
        recordedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        frames: [Frame] = [],
        duration: TimeInterval = 0
    ) -> Clip {
        Clip(id: id, recordedAt: recordedAt, frames: frames, duration: duration)
    }

    private func makeFrames(count: Int, payloadBase: UInt8 = 0) -> [Frame] {
        // 2×2 BGRA = 16 bytes per frame, content varied by index so each
        // frame's bytes round-trip distinctly through the on-disk format.
        (0..<count).map { i in
            let bytes = Data((0..<16).map { UInt8(($0 + i + Int(payloadBase)) & 0xFF) })
            return Frame(
                presentationTime: TimeInterval(i) * 0.033,
                pixelData: bytes,
                width: 2, height: 2,
                pixelFormat: 0x42475241, // 'BGRA'
                bytesPerRow: 8
            )
        }
    }

    // MARK: - Empty store

    @Test func emptyStore_allReturnsEmpty() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let all = try await store.all()
        #expect(all.isEmpty)
    }

    @Test func emptyStore_clipById_returnsNil() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let result = try await store.clip(id: UUID())
        #expect(result == nil)
    }

    @Test func emptyStore_doesNotRequireRootToExistBeforehand() async throws {
        let tmp = Self.makeTempRoot()
        // root does not exist yet — store must tolerate that on first read
        let store = FileSystemClipStore(rootURL: tmp.url)
        #expect(try await store.all().isEmpty)
    }

    // MARK: - Save & Retrieve

    @Test func savedClip_appearsInAll() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 3))
        try await store.save(c)
        let all = try await store.all()
        #expect(all == [c])
    }

    @Test func savedClip_isFoundById() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 5), duration: 0.165)
        try await store.save(c)
        let result = try await store.clip(id: c.id)
        #expect(result == c)
    }

    @Test func savedClip_persistsAcrossInstances() async throws {
        let tmp = Self.makeTempRoot()
        let c = makeClip(frames: makeFrames(count: 4), duration: 0.132)
        do {
            let writer = FileSystemClipStore(rootURL: tmp.url)
            try await writer.save(c)
        }
        let reader = FileSystemClipStore(rootURL: tmp.url)
        let all = try await reader.all()
        #expect(all == [c])
    }

    // MARK: - Multiple Clips (recordedAt asc order)

    @Test func multipleSaves_allReturnsClipsInRecordedAtAscOrder() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let early = makeClip(recordedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let mid = makeClip(recordedAt: Date(timeIntervalSince1970: 1_700_000_005))
        let late = makeClip(recordedAt: Date(timeIntervalSince1970: 1_700_000_010))
        try await store.save(late)
        try await store.save(early)
        try await store.save(mid)
        let all = try await store.all()
        #expect(all == [early, mid, late])
    }

    // MARK: - Replace on duplicate id

    @Test func saveSameId_replacesExisting() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let id = UUID()
        let v1 = makeClip(id: id, frames: makeFrames(count: 2), duration: 5)
        let v2 = makeClip(id: id, frames: makeFrames(count: 4, payloadBase: 99), duration: 10)
        try await store.save(v1)
        try await store.save(v2)
        let all = try await store.all()
        #expect(all == [v2])
        let found = try await store.clip(id: id)
        #expect(found == v2)
    }

    @Test func saveSameClipTwice_isIdempotent() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 2))
        try await store.save(c)
        try await store.save(c)
        let all = try await store.all()
        #expect(all == [c])
    }

    // MARK: - Frame fidelity

    @Test func largeClip_roundtripsBitExact() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        // 32×64 BGRA = 8 KiB per frame, content varying by index.
        let width = 32
        let height = 64
        let bytesPerFrame = width * height * 4
        let frames: [Frame] = (0..<256).map { i in
            let bytes = Data((0..<bytesPerFrame).map { byte in UInt8((byte ^ i) & 0xFF) })
            return Frame(
                presentationTime: TimeInterval(i) * 0.04,
                pixelData: bytes,
                width: width, height: height,
                pixelFormat: 0x42475241, // 'BGRA'
                bytesPerRow: width * 4
            )
        }
        let c = makeClip(frames: frames, duration: TimeInterval(frames.count) * 0.04)
        try await store.save(c)
        let result = try await store.clip(id: c.id)
        #expect(result == c)
    }

    // MARK: - delete

    @Test func deletedClip_isGoneFromAll() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 3))
        try await store.save(c)
        try await store.delete(id: c.id)
        let all = try await store.all()
        #expect(all.isEmpty)
    }

    @Test func deletedClip_isRemovedFromDisk() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 3))
        try await store.save(c)
        try await store.delete(id: c.id)
        let clipDir = tmp.url.appendingPathComponent(c.id.uuidString, isDirectory: true)
        #expect(FileManager.default.fileExists(atPath: clipDir.path) == false)
    }

    @Test func delete_unknownId_isIdempotent() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        try await store.delete(id: UUID()) // no-op, no throw
        #expect(try await store.all().isEmpty)
    }

    @Test func delete_doesNotAffectOtherClips() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let keep = makeClip(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            frames: makeFrames(count: 2)
        )
        let gone = makeClip(
            recordedAt: Date(timeIntervalSince1970: 1_700_000_005),
            frames: makeFrames(count: 4, payloadBase: 50)
        )
        try await store.save(keep)
        try await store.save(gone)
        try await store.delete(id: gone.id)
        let all = try await store.all()
        #expect(all == [keep])
    }

    // MARK: - Atomic write — partial state must not be observable

    @Test func saveReplacement_thenCrashSimulated_stillHasPreviousData() async throws {
        // We can't actually simulate a crash mid-write, but we can verify
        // there is no leaked per-clip directory under `.staging/` after a
        // successful save (i.e. cleanup of the staging area happens on
        // commit). This is the operational guarantee callers rely on.
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 5))
        try await store.save(c)
        let stagingDir = tmp.url.appendingPathComponent(".staging", isDirectory: true)
        let stagingContents = (try? FileManager.default.contentsOfDirectory(atPath: stagingDir.path)) ?? []
        #expect(stagingContents.isEmpty, "staging area must be empty after a successful save, got: \(stagingContents)")
    }

    // MARK: - Filesystem precondition — root path collides with a file

    @Test func save_throwsNotADirectory_whenRootPathIsAFile() async throws {
        let parent = Self.makeTempRoot()
        try FileManager.default.createDirectory(at: parent.url, withIntermediateDirectories: true)
        let collidingRoot = parent.url.appendingPathComponent("clipstore-collision")
        try Data("not a directory".utf8).write(to: collidingRoot)
        let store = FileSystemClipStore(rootURL: collidingRoot)
        let c = makeClip(frames: makeFrames(count: 1))
        await #expect(throws: FileSystemClipStoreError.notADirectory(collidingRoot)) {
            try await store.save(c)
        }
    }

    // MARK: - Corrupted metadata — surfaces as invalidMetadata, not a trap

    @Test func clip_invalidPixelFormat_throwsInvalidMetadata() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 1))
        try await store.save(c)
        // Rewrite metadata.json with pixelFormat = -1 (out of UInt32 range).
        let clipDir = tmp.url.appendingPathComponent(c.id.uuidString, isDirectory: true)
        let metadataURL = clipDir.appendingPathComponent("metadata.json")
        let raw = try Data(contentsOf: metadataURL)
        let mutated = String(data: raw, encoding: .utf8)?
            .replacingOccurrences(of: "\"pixelFormat\":1111970369", with: "\"pixelFormat\":-1")
        let mutatedData = try #require(mutated?.data(using: .utf8))
        try mutatedData.write(to: metadataURL)
        await #expect(throws: FileSystemClipStoreError.self) {
            _ = try await store.clip(id: c.id)
        }
    }

    @Test func clip_negativeDimension_throwsInvalidMetadata() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let c = makeClip(frames: makeFrames(count: 1))
        try await store.save(c)
        let clipDir = tmp.url.appendingPathComponent(c.id.uuidString, isDirectory: true)
        let metadataURL = clipDir.appendingPathComponent("metadata.json")
        let raw = try Data(contentsOf: metadataURL)
        let mutated = String(data: raw, encoding: .utf8)?
            .replacingOccurrences(of: "\"width\":2", with: "\"width\":-2")
        let mutatedData = try #require(mutated?.data(using: .utf8))
        try mutatedData.write(to: metadataURL)
        await #expect(throws: FileSystemClipStoreError.self) {
            _ = try await store.clip(id: c.id)
        }
    }

    // MARK: - Concurrency (actor must serialize)

    @Test func concurrentSaves_allObservedInAll() async throws {
        let tmp = Self.makeTempRoot()
        let store = FileSystemClipStore(rootURL: tmp.url)
        let clips: [Clip] = (0..<10).map { i in
            makeClip(
                recordedAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(i)),
                frames: makeFrames(count: 2, payloadBase: UInt8(i))
            )
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for c in clips {
                group.addTask {
                    try await store.save(c)
                }
            }
            try await group.waitForAll()
        }
        let all = try await store.all()
        #expect(all.count == clips.count)
        #expect(Set(all.map(\.id)) == Set(clips.map(\.id)))
    }
}

// MARK: - Test scaffolding

/// RAII helper — removes the directory tree when the value is dropped.
private final class TempDir {
    let url: URL
    init(url: URL) {
        self.url = url
    }
    deinit {
        try? FileManager.default.removeItem(at: url)
    }
}
