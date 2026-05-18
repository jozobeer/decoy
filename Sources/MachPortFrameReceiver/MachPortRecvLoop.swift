// COVERAGE: OS-direct wiring only ― MachPortFrameReceiver/MachPortRecvLoop.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Darwin
import Foundation

/// `mach_msg(MACH_RCV_MSG)` で receive port から `FrameMachMessage` を
/// 1 件ずつ取り出して `AsyncThrowingStream<IncomingFrameMessage, Error>`
/// に流す helper。
///
/// 構造：
/// - `Task.detached { ... }` で blocking recv を走らせる ― swift-concurrency
///   の cooperative thread を握り潰さないよう独立スレッドに逃がす。
/// - Task cancel で `mach_port_mod_refs(-1)` を呼び receive right を
///   破棄 → blocked `mach_msg` が `MACH_RCV_PORT_DIED` で抜ける。
/// - recv 失敗 (`MACH_MSG_SUCCESS` 以外) は stream を error で終端し
///   loop を抜ける。
///
/// Coverage note: `mach_msg` は実 IPC を必要とするためユニットテスト
/// 対象外。
enum MachPortRecvLoop {
    static func stream(receivePort: mach_port_t) -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        AsyncThrowingStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                recvLoop(receivePort: receivePort, continuation: continuation)
            }
            continuation.onTermination = { _ in
                task.cancel()
                _ = mach_port_mod_refs(mach_task_self_, receivePort, MACH_PORT_RIGHT_RECEIVE, -1)
            }
        }
    }

    private static func recvLoop(
        receivePort: mach_port_t,
        continuation: AsyncThrowingStream<IncomingFrameMessage, Error>.Continuation
    ) {
        var message = FrameMachMessageWithTrailer()
        // Mach recv buffer は message 本体に加えて kernel が付与する
        // trailer 分の余白が要る。足りないと `MACH_RCV_TOO_LARGE` で
        // 第一通から失敗する。`mach_msg_max_trailer_t` のサイズで包む。
        let bufferSize = mach_msg_size_t(MemoryLayout<FrameMachMessageWithTrailer>.size)
        while !Task.isCancelled {
            let result = withUnsafeMutablePointer(to: &message.message.header) { headerPtr in
                mach_msg(headerPtr, MACH_RCV_MSG, 0, bufferSize, receivePort, MACH_MSG_TIMEOUT_NONE, mach_port_t(MACH_PORT_NULL))
            }
            guard result == MACH_MSG_SUCCESS else {
                continuation.finish(throwing: MachPortReceiverError.recvFailed(code: Int(result)))
                return
            }
            // Defensive header validation. host (`MachPortMessageSender`)
            // emits exactly this shape; anything else is a malformed /
            // foreign message and must be destroyed rather than decoded
            // (reading `surfacePort.name` on a wrong-shaped buffer would
            // either reference garbage or leak the receive side of an
            // unrelated send right that landed in the port queue).
            let bits = message.message.header.msgh_bits & mach_msg_bits_t(MACH_MSGH_BITS_COMPLEX)
            guard message.message.header.msgh_id == FrameMachMessage.id,
                  bits != 0,
                  message.message.body.msgh_descriptor_count == 1 else {
                withUnsafeMutablePointer(to: &message.message.header) { headerPtr in
                    mach_msg_destroy(headerPtr)
                }
                continue
            }
            continuation.yield(IncomingFrameMessage(
                surfacePort: ReceiverMachPortToken(raw: UInt32(message.message.surfacePort.name)),
                presentationTime: TimeInterval(message.message.presentationTime),
                width: Int(message.message.width),
                height: Int(message.message.height)
            ))
        }
        continuation.finish()
    }
}

/// extension 側で受け取る Mach message layout ―
/// `Sources/MachPortFrameTransport/MachPortMessageSender.swift` の
/// `FrameMachMessage` と完全一致。host / extension 間の wire format
/// 共有契約。
struct FrameMachMessage {
    static let id: mach_msg_id_t = 0x10001

    var header: mach_msg_header_t = mach_msg_header_t()
    var body: mach_msg_body_t = mach_msg_body_t()
    var surfacePort: mach_msg_port_descriptor_t = mach_msg_port_descriptor_t()
    var presentationTime: Float64 = 0
    var width: UInt32 = 0
    var height: UInt32 = 0
}

/// recv 用 buffer ― 本体 + kernel が付与する trailer 分。
/// `mach_msg(MACH_RCV_MSG)` の receive size には trailer 込みで渡す。
struct FrameMachMessageWithTrailer {
    var message: FrameMachMessage = FrameMachMessage()
    var trailer: mach_msg_max_trailer_t = mach_msg_max_trailer_t()
}
