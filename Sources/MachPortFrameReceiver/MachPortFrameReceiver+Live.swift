// COVERAGE: OS-direct wiring only ― MachPortFrameReceiver/MachPortFrameReceiver+Live.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Foundation

extension MachPortFrameReceiver {
    /// extension 本体から呼ぶ live factory。`bootstrap_check_in` の live
    /// server と `IOSurfaceLookupFromMachPort` の live materializer を
    /// 配線する。
    public static func live(serviceName: String) -> MachPortFrameReceiver {
        MachPortFrameReceiver(
            serviceName: serviceName,
            server: BootstrapMachPortCheckIn(),
            materializer: IOSurfaceLookupMaterializer()
        )
    }
}
