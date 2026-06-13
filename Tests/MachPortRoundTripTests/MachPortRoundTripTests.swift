import Domain
import Foundation
import MachPortFrameReceiver
import MachPortFrameTransport
import Testing

/// host 側 (`MachPortFrameTransport`) と extension 側
/// (`MachPortFrameReceiver`) の abstraction boundary をまたぐ
/// contract test。実 Mach port / IOSurface は触らず、
/// `RelayChannel` がプロセス内で双方向 relay する。
///
/// 目的：両モジュールの public API を組み合わせたとき、
/// transport.send() で送った frame の metadata が
/// receiver.frames から正しく届くことを検証する。
@Suite("MachPort round-trip", .serialized, .timeLimit(.minutes(1)))
struct MachPortRoundTripTests {

    private static func makeFrame(pts: TimeInterval = 1.0, byte: UInt8 = 0xAB) -> Frame {
        Frame(
            presentationTime: pts,
            pixelData: Data(repeating: byte, count: 64),
            width: 4,
            height: 4,
            pixelFormat: 0x42475241,
            bytesPerRow: 16
        )
    }

    // MARK: - round-trip tests

    @Test
    func oneFrame_sentByTransport_receivedByReceiver() async throws {
        let channel = RelayChannel()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.roundtrip",
            lookup: ConstantLookup(token: MachPortToken(raw: 1)),
            sender: channel
        )
        let receiver = MachPortFrameReceiver(
            serviceName: "decoy.roundtrip",
            server: channel,
            materializer: MetadataOnlyMaterializer()
        )

        let frames = await receiver.frames
        try await receiver.start()
        try await transport.connect()

        let original = Self.makeFrame(pts: 1.234)
        try await transport.send(original)

        var received: [Frame] = []
        for await frame in frames {
            received.append(frame)
            if received.count == 1 { break }
        }

        let got = try #require(received.first)
        #expect(got.presentationTime == original.presentationTime)
        #expect(got.width == original.width)
        #expect(got.height == original.height)
    }

    @Test
    func multipleFrames_preserveOrder() async throws {
        let channel = RelayChannel()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.roundtrip",
            lookup: ConstantLookup(token: MachPortToken(raw: 1)),
            sender: channel
        )
        let receiver = MachPortFrameReceiver(
            serviceName: "decoy.roundtrip",
            server: channel,
            materializer: MetadataOnlyMaterializer()
        )

        let frames = await receiver.frames
        try await receiver.start()
        try await transport.connect()

        let timestamps: [TimeInterval] = [0.1, 0.2, 0.3]
        for pts in timestamps {
            try await transport.send(Self.makeFrame(pts: pts))
        }

        var received: [TimeInterval] = []
        for await frame in frames {
            received.append(frame.presentationTime)
            if received.count == timestamps.count { break }
        }

        #expect(received == timestamps)
    }

    @Test
    func channelFinish_endsReceiverStream() async throws {
        let channel = RelayChannel()
        let transport = MachPortFrameTransport(
            serviceName: "decoy.roundtrip",
            lookup: ConstantLookup(token: MachPortToken(raw: 1)),
            sender: channel
        )
        let receiver = MachPortFrameReceiver(
            serviceName: "decoy.roundtrip",
            server: channel,
            materializer: MetadataOnlyMaterializer()
        )

        let frames = await receiver.frames
        try await receiver.start()
        try await transport.connect()

        try await transport.send(Self.makeFrame())

        await channel.finish()

        var count = 0
        for await _ in frames { count += 1 }

        #expect(count == 1)
    }
}

// MARK: - RelayChannel

/// `MachPortSender` と `MachPortServer` を同時に実装する
/// in-process relay。transport が `send()` で流した Frame を
/// `IncomingFrameMessage` に変換し、receiver の
/// `AsyncThrowingStream` に直接 yield する。
private actor RelayChannel: MachPortSender, MachPortServer {
    private var continuation: AsyncThrowingStream<IncomingFrameMessage, Error>.Continuation?
    private var portCounter: UInt32 = 1

    // MachPortServer
    func messages(serviceName: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        let (stream, cont) = AsyncThrowingStream.makeStream(of: IncomingFrameMessage.self)
        continuation = cont
        return stream
    }

    func stop() async {
        continuation?.finish()
        continuation = nil
    }

    // MachPortSender
    func send(frame: Frame, via port: MachPortToken) async throws {
        let msg = IncomingFrameMessage(
            surfacePort: ReceiverMachPortToken(raw: portCounter),
            presentationTime: frame.presentationTime,
            width: frame.width,
            height: frame.height
        )
        portCounter += 1
        continuation?.yield(msg)
    }

    func release(port: MachPortToken) async {}

    func finish() {
        continuation?.finish()
        continuation = nil
    }
}

// MARK: - Fakes

private struct ConstantLookup: MachPortLookup {
    let token: MachPortToken
    func lookUp(serviceName: String) async throws -> MachPortToken { token }
}

/// IOSurface を使わず IncomingFrameMessage の metadata だけで
/// Frame を再構成する。round-trip では pixelData は検証対象外
/// (実 Mach port / IOSurface なしで pixel bytes を round-trip
/// させる経路は存在しない)。
private struct MetadataOnlyMaterializer: IOSurfaceMaterializer {
    func frame(from message: IncomingFrameMessage) async throws -> Frame {
        Frame(
            presentationTime: message.presentationTime,
            pixelData: Data(),
            width: message.width,
            height: message.height,
            pixelFormat: 0x42475241,
            bytesPerRow: message.width * 4
        )
    }
}
