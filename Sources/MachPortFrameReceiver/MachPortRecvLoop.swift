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
        var message = FrameMachMessage()
        while !Task.isCancelled {
            let size = mach_msg_size_t(MemoryLayout<FrameMachMessage>.size)
            let result = withUnsafeMutablePointer(to: &message.header) { headerPtr in
                mach_msg(headerPtr, MACH_RCV_MSG, 0, size, receivePort, MACH_MSG_TIMEOUT_NONE, mach_port_t(MACH_PORT_NULL))
            }
            guard result == MACH_MSG_SUCCESS else {
                continuation.finish(throwing: MachPortReceiverError.recvFailed(code: Int(result)))
                return
            }
            continuation.yield(IncomingFrameMessage(
                surfacePort: ReceiverMachPortToken(raw: UInt32(message.surfacePort.name)),
                presentationTime: TimeInterval(message.presentationTime),
                width: Int(message.width),
                height: Int(message.height)
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
