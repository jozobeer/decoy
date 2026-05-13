import Foundation

public protocol ClipStore: Sendable {
    func save(_ clip: Clip) async throws
    func all() async throws -> [Clip]
    func clip(id: UUID) async throws -> Clip?
    /// Removes the clip with the given id.
    ///
    /// Deletion is idempotent: calling `delete` for an id that is not present
    /// must complete normally without throwing. Implementations may still
    /// throw for I/O failures unrelated to existence (e.g. permission errors).
    func delete(id: UUID) async throws
}
