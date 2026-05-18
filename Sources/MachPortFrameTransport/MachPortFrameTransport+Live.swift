// COVERAGE: OS-direct wiring only ― MachPortFrameTransport/MachPortFrameTransport+Live.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Domain

/// Live-wiring helper. `BootstrapMachPortLookup` + `MachPortMessageSender`
/// を組み合わせて `MachPortFrameTransport` actor を構築する。
///
/// service name は明示渡しを必須とする ― IPC wire 識別子は host /
/// extension で必ず同じ string を握る必要があり、default に倒すと
/// 片方を変更したときに silent な mismatch を起こすため。共有定数は
/// `FrameTransportServiceName.mach` (Domain)。
///
/// Coverage note: bootstrap / mach_msg / IOSurface mach port は実 Mach
/// pair でしか exercise できないため coverage 対象外。
public extension MachPortFrameTransport {
    static func live(serviceName: String) -> MachPortFrameTransport {
        MachPortFrameTransport(
            serviceName: serviceName,
            lookup: BootstrapMachPortLookup(),
            sender: MachPortMessageSender()
        )
    }
}
