import Dependencies
import Domain
import InMemoryClipStore

extension ClipStoreKey: DependencyKey {
    public static let liveValue: any ClipStore = InMemoryClipStore()
}
