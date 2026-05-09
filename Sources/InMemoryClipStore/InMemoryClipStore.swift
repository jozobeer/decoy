import Foundation
import Domain

public actor InMemoryClipStore: ClipStore {
    private var clips: [UUID: Clip] = [:]

    public init() {}

    public func save(_ clip: Clip) async throws {
        // tdd-impl phase: not yet implemented
    }

    public func all() async throws -> [Clip] {
        []
    }

    public func clip(id: UUID) async throws -> Clip? {
        nil
    }
}
