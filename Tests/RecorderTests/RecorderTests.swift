import Testing
import Domain
@testable import Recorder

@Suite("Recorder")
struct RecorderTests {
    @Test func defaultInit_startsIdle() async {
        let recorder = Recorder()
        #expect(await recorder.state == .idle)
    }
}
