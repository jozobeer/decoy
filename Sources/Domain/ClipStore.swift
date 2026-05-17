import Dependencies
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

public enum ClipStoreKey: TestDependencyKey {
    public static let testValue: any ClipStore = UnimplementedClipStore()
}

extension DependencyValues {
    public var clipStore: any ClipStore {
        get { self[ClipStoreKey.self] }
        set { self[ClipStoreKey.self] = newValue }
    }
}

private struct UnimplementedClipStore: ClipStore {
    func save(_ clip: Clip) async throws {
        reportIssue(#"@Dependency(\.clipStore)"#)
    }
    func all() async throws -> [Clip] {
        reportIssue(#"@Dependency(\.clipStore)"#)
        return []
    }
    func clip(id: UUID) async throws -> Clip? {
        reportIssue(#"@Dependency(\.clipStore)"#)
        return nil
    }
    func delete(id: UUID) async throws {
        reportIssue(#"@Dependency(\.clipStore)"#)
    }
}
