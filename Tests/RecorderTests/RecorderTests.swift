import Testing
import Domain
@testable import Recorder

@Suite("Recorder")
struct RecorderTests {
    // MARK: - Construction

    @Test func defaultInit_startsIdle() async {
        let recorder = Recorder()
        #expect(await recorder.state == .idle)
    }

    @Test func explicitInit_preservesGivenState() async {
        let recorder = Recorder(state: .recording)
        #expect(await recorder.state == .recording)
    }

    // MARK: - Normal Behavior

    @Test func startRecording_fromIdle_setsRecording() async {
        let recorder = Recorder(state: .idle)
        await recorder.handle(.startRecording)
        #expect(await recorder.state == .recording)
    }

    @Test func stopRecording_fromRecording_setsIdle() async {
        let recorder = Recorder(state: .recording)
        await recorder.handle(.stopRecording)
        #expect(await recorder.state == .idle)
    }

    // MARK: - Ignore Foreign Commands

    @Test(arguments: [RecordingState.idle, .recording],
                     [AppCommand.startDecoy(.once), .startDecoy(.loop), .startDecoy(.pingPong), .returnToLive])
    func ignoresForeignCommand(initial: RecordingState, foreign: AppCommand) async {
        let recorder = Recorder(state: initial)
        await recorder.handle(foreign)
        #expect(await recorder.state == initial)
    }

    // MARK: - Idempotency

    @Test func startRecording_whenAlreadyRecording_isNoOp() async {
        let recorder = Recorder(state: .recording)
        await recorder.handle(.startRecording)
        #expect(await recorder.state == .recording)
    }

    @Test func stopRecording_whenAlreadyIdle_isNoOp() async {
        let recorder = Recorder(state: .idle)
        await recorder.handle(.stopRecording)
        #expect(await recorder.state == .idle)
    }
}
