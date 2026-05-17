import Testing
import Domain
@testable import RecorderUseCase

@Suite("RecorderUseCaseImpl")
struct RecorderTests {
    @Test func defaultInit_startsIdle() async {
        let recorder = RecorderUseCaseImpl()
        #expect(await recorder.state == .idle)
    }
}
