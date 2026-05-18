// COVERAGE: OS-direct wiring only ― MachPortFrameReceiver/BootstrapMachPortCheckIn.swift
// is listed in codecov.yml ignore. See .claude/rules/coverage-ignored-modules.md
// "+Live.swift extension pattern" for the contract.

import Darwin
import Foundation

/// `bootstrap_check_in(3)` + `mach_msg` recv loop の live 実装。
///
/// `messages(serviceName:)`:
/// 1. `bootstrap_check_in` で service name を launchd に登録 ― receive
///    right を得る。所有は recv loop の `AsyncThrowingStream`
///    `onTermination` に委譲され、stream が終わる時 (subscriber drop /
///    receiver `stop()` / Task cancel) に
///    `mach_port_mod_refs(MACH_PORT_RIGHT_RECEIVE, -1)` で破棄される。
/// 2. background `Task.detached` で `mach_msg(MACH_RCV_MSG)` を回し、
///    1 message ごとに `FrameMachMessage` 形式で decode ―
///    `IncomingFrameMessage` を `AsyncThrowingStream` に yield。
///
/// `stop()`:
/// - server は receive port を所有しないため no-op。停止経路は
///   orchestrator (`MachPortFrameReceiver.stop()`) が
///   `listenTask?.cancel()` → stream `onTermination` を発火 →
///   `mach_port_mod_refs(-1)` という cancel-propagation で実現する。
///
/// Coverage note: bootstrap_check_in / mach_msg は launchd と実 IPC を
/// 必要とするためユニットテスト対象外。orchestrator
/// (`MachPortFrameReceiver`) のテストは in-process な
/// `AsyncThrowingStream` fake が担保。
public struct BootstrapMachPortCheckIn: MachPortServer {
    public init() {}
}

extension BootstrapMachPortCheckIn {
    public func messages(serviceName: String) async throws -> AsyncThrowingStream<IncomingFrameMessage, Error> {
        var bp: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let bootstrapResult = task_get_special_port(mach_task_self_, TASK_BOOTSTRAP_PORT, &bp)
        guard bootstrapResult == KERN_SUCCESS else {
            throw MachPortReceiverError.checkInFailed(serviceName: serviceName, code: Int(bootstrapResult))
        }
        defer { _ = mach_port_deallocate(mach_task_self_, bp) }
        var port: mach_port_t = mach_port_t(MACH_PORT_NULL)
        let result = serviceName.withCString { cName in
            decoy_bootstrap_check_in(bp, cName, &port)
        }
        guard result == KERN_SUCCESS else {
            throw MachPortReceiverError.checkInFailed(serviceName: serviceName, code: Int(result))
        }
        return MachPortRecvLoop.stream(receivePort: port)
    }

    public func stop() async {
        // receive port の所有は `AsyncThrowingStream` の `onTermination`
        // (in `MachPortRecvLoop.stream`) に委譲済みのため、server 単体での
        // stop は no-op。停止経路は orchestrator の listenTask cancel が
        // stream onTermination を発火させる cancel-propagation で実現。
    }
}

@_silgen_name("bootstrap_check_in")
private func decoy_bootstrap_check_in(
    _ bp: mach_port_t,
    _ serviceName: UnsafePointer<CChar>,
    _ sp: UnsafeMutablePointer<mach_port_t>
) -> kern_return_t
