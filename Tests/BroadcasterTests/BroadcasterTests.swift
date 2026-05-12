import Testing
import Domain
@testable import Broadcaster

@Suite("Broadcaster")
struct BroadcasterTests {
    // MARK: - Construction

    @Test func defaultInit_isLive() async {
        let broadcaster = Broadcaster()
        #expect(await broadcaster.state == .live)
    }

    @Test(arguments: [
        OutputMode.live,
        .playback(.once),
        .playback(.loop),
        .playback(.pingPong),
    ])
    func explicitInit_preservesGivenState(initial: OutputMode) async {
        let broadcaster = Broadcaster(state: initial)
        #expect(await broadcaster.state == initial)
    }

    // MARK: - Normal Behavior

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func startDecoy_fromLive_setsPlaybackWithGivenMode(mode: PlaybackMode) async {
        let broadcaster = Broadcaster(state: .live)
        await broadcaster.handle(.startDecoy(mode))
        #expect(await broadcaster.state == .playback(mode))
    }

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func returnToLive_fromAnyPlayback_setsLive(mode: PlaybackMode) async {
        let broadcaster = Broadcaster(state: .playback(mode))
        await broadcaster.handle(.returnToLive)
        #expect(await broadcaster.state == .live)
    }

    // MARK: - Mode Switching mid-playback (startDecoy from playback)

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong],
                     [PlaybackMode.once, .loop, .pingPong])
    func startDecoy_fromPlayback_switchesToTargetMode(initial: PlaybackMode, target: PlaybackMode) async {
        let broadcaster = Broadcaster(state: .playback(initial))
        await broadcaster.handle(.startDecoy(target))
        #expect(await broadcaster.state == .playback(target))
    }

    // MARK: - Ignore Foreign Commands

    @Test(arguments: [
        OutputMode.live,
        .playback(.once),
        .playback(.loop),
        .playback(.pingPong),
    ],
    [AppCommand.startRecording, .stopRecording])
    func ignoresForeignCommand(initial: OutputMode, foreign: AppCommand) async {
        let broadcaster = Broadcaster(state: initial)
        await broadcaster.handle(foreign)
        #expect(await broadcaster.state == initial)
    }

    // MARK: - Idempotency

    @Test(arguments: [PlaybackMode.once, .loop, .pingPong])
    func startDecoy_whenAlreadyPlaybackSameMode_isNoOp(mode: PlaybackMode) async {
        let initial = OutputMode.playback(mode)
        let broadcaster = Broadcaster(state: initial)
        await broadcaster.handle(.startDecoy(mode))
        #expect(await broadcaster.state == initial)
    }

    @Test func returnToLive_whenAlreadyLive_isNoOp() async {
        let broadcaster = Broadcaster(state: .live)
        await broadcaster.handle(.returnToLive)
        #expect(await broadcaster.state == .live)
    }

    // MARK: - Same-dim Last-Write-Wins

    @Test func startDecoy_chain_lastModeWins() async {
        let broadcaster = Broadcaster(state: .live)
        await broadcaster.handle(.startDecoy(.once))
        await broadcaster.handle(.startDecoy(.loop))
        await broadcaster.handle(.startDecoy(.pingPong))
        #expect(await broadcaster.state == .playback(.pingPong))
    }

    @Test func startDecoy_then_returnToLive_endsAtLive() async {
        let broadcaster = Broadcaster(state: .live)
        await broadcaster.handle(.startDecoy(.loop))
        await broadcaster.handle(.returnToLive)
        #expect(await broadcaster.state == .live)
    }
}
