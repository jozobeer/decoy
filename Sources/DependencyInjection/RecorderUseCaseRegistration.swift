import Dependencies
import Domain
import RecorderUseCase

extension RecorderUseCaseKey: DependencyKey {
    public static let liveValue: any RecorderUseCase = RecorderUseCaseImpl()
}
