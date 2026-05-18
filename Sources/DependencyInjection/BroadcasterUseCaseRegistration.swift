import BroadcasterUseCase
import Dependencies
import Domain

extension BroadcasterUseCaseKey: DependencyKey {
    public static let liveValue: any BroadcasterUseCase = BroadcasterUseCaseImpl()
}
