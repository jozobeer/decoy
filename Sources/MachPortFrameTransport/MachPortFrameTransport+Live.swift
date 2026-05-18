// COVERAGE: OS-direct wiring only ― MachPortFrameTransport/MachPortFrameTransport+Live.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Foundation

/// Live-wiring helper. `BootstrapMachPortLookup` + `MachPortMessageSender`
/// を組み合わせて `MachPortFrameTransport` actor を構築する。
///
/// Coverage note: bootstrap / mach_msg / IOSurface mach port は実 Mach
/// pair でしか exercise できないため coverage 対象外。
public extension MachPortFrameTransport {
    static func live(serviceName: String = "beer.jozo.decoy.CameraExtension.transport") -> MachPortFrameTransport {
        MachPortFrameTransport(
            serviceName: serviceName,
            lookup: BootstrapMachPortLookup(),
            sender: MachPortMessageSender()
        )
    }
}
