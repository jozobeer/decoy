import Foundation
import Domain

public actor InMemoryClipStore: ClipStore {
    private var clips: [UUID: Clip] = [:]

    public init() {}

    public func save(_ clip: Clip) async throws {
        clips[clip.id] = clip
    }

    public func all() async throws -> [Clip] {
        clips.values.sorted { $0.recordedAt < $1.recordedAt }
    }

    public func clip(id: UUID) async throws -> Clip? {
        clips[id]
    }

    public func delete(id: UUID) async throws {
        clips.removeValue(forKey: id)
    }
}
