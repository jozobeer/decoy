import Dependencies
import Domain
import InMemoryClipStore

extension DependencyValues {
    public var clipStore: any ClipStore {
        get { self[ClipStoreKey.self] }
        set { self[ClipStoreKey.self] = newValue }
    }
}

private enum ClipStoreKey: DependencyKey {
    static let liveValue: any ClipStore = InMemoryClipStore()
    static let testValue: any ClipStore = InMemoryClipStore()
}
