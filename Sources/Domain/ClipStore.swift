import Foundation

public protocol ClipStore: Sendable {
    func save(_ clip: Clip) async throws
    func all() async throws -> [Clip]
    func clip(id: UUID) async throws -> Clip?
}
