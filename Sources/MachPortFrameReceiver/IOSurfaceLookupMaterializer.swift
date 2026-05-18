// COVERAGE: OS-direct wiring only ― MachPortFrameReceiver/IOSurfaceLookupMaterializer.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Darwin
import Domain
import Foundation
@preconcurrency import IOSurface
import IOSurfaceFactory

/// `IOSurfaceMaterializer` の live 実装。
///
/// 1. `IOSurfaceLookupFromMachPort(port)` で send right から IOSurface
///    ref を解決。失敗時は `surfaceLookupFailed`。
/// 2. `IOSurfaceFactory.readBytes(_:)` で pixel bytes を Data に複製
///    (host 側と同じ format ― BGRA を想定。pixelFormat / bytesPerRow は
///    surface 自身から読む)。
/// 3. 解決し終わった send right は `mach_port_deallocate` で release ―
///    放置すると extension プロセスの port table が枯渇する。
///
/// Coverage note: `IOSurfaceLookupFromMachPort` は実 Mach port + 実 IOSurface
/// を要求するためユニットテスト対象外。orchestrator side は in-process
/// fake materializer でカバー済み。
public struct IOSurfaceLookupMaterializer: IOSurfaceMaterializer {
    public init() {}
}

extension IOSurfaceLookupMaterializer {
    public func frame(from message: IncomingFrameMessage) async throws -> Frame {
        let port = mach_port_t(message.surfacePort.raw)
        defer { _ = mach_port_deallocate(mach_task_self_, port) }
        guard let surface = IOSurfaceLookupFromMachPort(port) else {
            throw MachPortReceiverError.surfaceLookupFailed(code: Int(KERN_INVALID_NAME))
        }
        let bytes = try IOSurfaceFactory.readBytes(surface)
        return Frame(
            presentationTime: message.presentationTime,
            pixelData: bytes,
            width: IOSurfaceGetWidth(surface),
            height: IOSurfaceGetHeight(surface),
            pixelFormat: IOSurfaceGetPixelFormat(surface),
            bytesPerRow: IOSurfaceGetBytesPerRow(surface)
        )
    }
}
