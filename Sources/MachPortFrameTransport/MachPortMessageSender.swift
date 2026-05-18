// COVERAGE: OS-direct wiring only ― MachPortFrameTransport/MachPortMessageSender.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Darwin
import Domain
import Foundation
import IOSurface
import IOSurfaceFactory

/// `MachPortSender` の live 実装。
///
/// `send(frame:via:)`:
/// 1. `IOSurfaceFactory.make(...)` で frame の pixelData から
///    `IOSurface` を materialize。
/// 2. `IOSurfaceCreateMachPort(_:)` で IOSurface に対応する mach_port
///    (send right) を得る ― caller (this method) に release 責任。
/// 3. `FrameMachMessage` (mach_msg header + body + port descriptor +
///    presentation time + dimensions) を組み立て、`mach_msg` で送る。
///    `MACH_MSG_TYPE_MOVE_SEND` を使うので kernel が send right を消費
///    する ― 送信成功時は明示的な `mach_port_deallocate` は不要。
///
/// `release(port:)`:
/// - `mach_port_deallocate(mach_task_self_, port)` で
///   `bootstrap_look_up` から得た送信権を解放する。
///
/// Coverage note: mach_msg / IOSurface mach port API は実 IPC pair で
/// しか exercise できないため coverage 除外。orchestrator
/// (`MachPortFrameTransport`) のテストは in-process fake が担保。
public struct MachPortMessageSender: MachPortSender {
    public init() {}
}

extension MachPortMessageSender {
    public func send(frame: Frame, via port: MachPortToken) async throws {
        let surface = try IOSurfaceFactory.make(
            width: frame.width,
            height: frame.height,
            pixelFormat: frame.pixelFormat,
            bytesPerElement: 4,
            bytesPerRow: frame.bytesPerRow,
            bytes: frame.pixelData
        )
        guard let surfacePort = IOSurfaceCreateMachPort(surface) as mach_port_t? else {
            throw MachPortTransportError.sendFailed(code: Int(KERN_RESOURCE_SHORTAGE))
        }
        var message = FrameMachMessage()
        message.header.msgh_bits = mach_msg_bits_t(MACH_MSGH_BITS_COMPLEX) | mach_msg_bits_t(MACH_MSG_TYPE_COPY_SEND)
        message.header.msgh_size = mach_msg_size_t(MemoryLayout<FrameMachMessage>.size)
        message.header.msgh_remote_port = mach_port_t(port.raw)
        message.header.msgh_local_port = mach_port_t(MACH_PORT_NULL)
        message.header.msgh_id = FrameMachMessage.id
        message.body.msgh_descriptor_count = 1
        message.surfacePort.name = surfacePort
        message.surfacePort.disposition = mach_msg_type_name_t(MACH_MSG_TYPE_MOVE_SEND)
        message.surfacePort.type = mach_msg_descriptor_type_t(MACH_MSG_PORT_DESCRIPTOR)
        message.presentationTime = Float64(frame.presentationTime)
        message.width = UInt32(frame.width)
        message.height = UInt32(frame.height)
        let messageSize = message.header.msgh_size
        let result = withUnsafeMutablePointer(to: &message.header) { headerPtr in
            mach_msg(
                headerPtr,
                MACH_SEND_MSG,
                messageSize,
                0,
                mach_port_t(MACH_PORT_NULL),
                MACH_MSG_TIMEOUT_NONE,
                mach_port_t(MACH_PORT_NULL)
            )
        }
        guard result == MACH_MSG_SUCCESS else {
            throw MachPortTransportError.sendFailed(code: Int(result))
        }
    }

    public func release(port: MachPortToken) async {
        _ = mach_port_deallocate(mach_task_self_, mach_port_t(port.raw))
    }
}

/// host → extension 間で送る固定サイズ Mach message。
///
/// Layout (host / extension で共有契約):
/// - `header` ― mach_msg_header_t (24 B)
/// - `body` ― 1 port descriptor を持つことを示す
/// - `surfacePort` ― IOSurfaceCreateMachPort で得た send right
/// - `presentationTime` / `width` / `height` ― frame metadata
///
/// Swift import 後の各 Mach type は naturally aligned に設計されており、
/// 明示パッキングなしで C struct と同じ layout に揃う。
private struct FrameMachMessage {
    static let id: mach_msg_id_t = 0x10001

    var header: mach_msg_header_t = mach_msg_header_t()
    var body: mach_msg_body_t = mach_msg_body_t()
    var surfacePort: mach_msg_port_descriptor_t = mach_msg_port_descriptor_t()
    var presentationTime: Float64 = 0
    var width: UInt32 = 0
    var height: UInt32 = 0
}
