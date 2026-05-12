import Testing
import Foundation
import Domain
@testable import InMemoryClipStore

@Suite("InMemoryClipStore")
struct InMemoryClipStoreTests {
    // MARK: - Helpers

    private func makeClip(
        id: UUID = UUID(),
        recordedAt: Date = Date(timeIntervalSince1970: 1_700_000_000),
        duration: TimeInterval = 0
    ) -> Clip {
        Clip(id: id, recordedAt: recordedAt, frames: [], duration: duration)
    }

    // MARK: - Empty store

    @Test func emptyStore_allReturnsEmpty() async throws {
        let store = InMemoryClipStore()
        let all = try await store.all()
        #expect(all.isEmpty)
    }

    @Test func emptyStore_clipById_returnsNil() async throws {
        let store = InMemoryClipStore()
        let result = try await store.clip(id: UUID())
        #expect(result == nil)
    }

    // MARK: - Save & Retrieve

    @Test func savedClip_appearsInAll() async throws {
        let store = InMemoryClipStore()
        let c = makeClip()
        try await store.save(c)
        let all = try await store.all()
        #expect(all == [c])
    }

    @Test func savedClip_isFoundById() async throws {
        let store = InMemoryClipStore()
        let c = makeClip()
        try await store.save(c)
        let result = try await store.clip(id: c.id)
        #expect(result == c)
    }

    // MARK: - Multiple Clips (recordedAt asc order)

    @Test func multipleSaves_allReturnsClipsInRecordedAtAscOrder() async throws {
        let store = InMemoryClipStore()
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
        let store = InMemoryClipStore()
        let id = UUID()
        let v1 = makeClip(id: id, duration: 5)
        let v2 = makeClip(id: id, duration: 10)
        try await store.save(v1)
        try await store.save(v2)
        let all = try await store.all()
        #expect(all == [v2])
        let found = try await store.clip(id: id)
        #expect(found == v2)
    }

    @Test func saveSameClipTwice_isIdempotent() async throws {
        let store = InMemoryClipStore()
        let c = makeClip()
        try await store.save(c)
        try await store.save(c)
        let all = try await store.all()
        #expect(all == [c])
    }

    // MARK: - clip(id:) miss

    @Test func clipById_unknownId_returnsNil() async throws {
        let store = InMemoryClipStore()
        try await store.save(makeClip())
        let result = try await store.clip(id: UUID())
        #expect(result == nil)
    }
}
