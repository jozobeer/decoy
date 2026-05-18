// COVERAGE: OS-direct wiring only ― MachPortFrameTransport/BootstrapMachPortLookup.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Darwin
import Foundation

/// `bootstrap_look_up(3)` を呼び出して service name から send right を
/// 解決する `MachPortLookup` の live 実装。失敗時は KERN error code を
/// `MachPortTransportError.lookupFailed` に包んで投げる。
///
/// Swift の Darwin overlay は `bootstrap_port` (global) を露出するが
/// `bootstrap_look_up` 関数本体は出していないため、`@_silgen_name` で
/// C シンボルを直接参照する。signature は `<servers/bootstrap.h>` の
/// `kern_return_t bootstrap_look_up(mach_port_t, const name_t, mach_port_t *)`
/// に一致させる。
///
/// Coverage note: `bootstrap_port` と `bootstrap_look_up` は launchd の
/// XPC bootstrap server に問い合わせる ― ユニットテストでは触れない。
/// orchestrator (`MachPortFrameTransport`) 側は in-process な fake で
/// 検証済み。
public struct BootstrapMachPortLookup: MachPortLookup {
    public init() {}
}

extension BootstrapMachPortLookup {
    public func lookUp(serviceName: String) async throws -> MachPortToken {
        var bp: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let bootstrapResult = task_get_special_port(mach_task_self_, TASK_BOOTSTRAP_PORT, &bp)
        guard bootstrapResult == KERN_SUCCESS else {
            throw MachPortTransportError.lookupFailed(serviceName: serviceName, code: Int(bootstrapResult))
        }
        // `task_get_special_port` は bootstrap port の send right を渡す ―
        // caller (この関数) に release 責任があり、放置するとプロセス毎の
        // port table を消費し続ける。lookup 成否どちらでも一度ずつ確実に
        // 解放するため defer に積む。
        defer { _ = mach_port_deallocate(mach_task_self_, bp) }
        var port: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let result = serviceName.withCString { cName in
            decoy_bootstrap_look_up(bp, cName, &port)
        }
        guard result == KERN_SUCCESS else {
            throw MachPortTransportError.lookupFailed(serviceName: serviceName, code: Int(result))
        }
        return MachPortToken(raw: port)
    }
}

@_silgen_name("bootstrap_look_up")
private func decoy_bootstrap_look_up(
    _ bp: mach_port_t,
    _ serviceName: UnsafePointer<CChar>,
    _ sp: UnsafeMutablePointer<mach_port_t>
) -> kern_return_t
