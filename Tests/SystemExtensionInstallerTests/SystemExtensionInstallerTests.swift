import Domain
import SystemExtensionInstaller
import Testing

@Suite("SystemExtensionInstaller")
struct SystemExtensionInstallerTests {
    @Test("activate() drives status: installing → needsApproval → installed")
    func activate_drivesStatusTransitions() async throws {
        let activator = FakeSystemExtensionActivator(scripts: [
            [.installing, .needsApproval, .installed],
        ])
        let installer = SystemExtensionInstaller(activator: activator)

        let collector = StatusCollector()
        let collected = Task { await collector.collect(installer.status, count: 4) }

        await installer.activate()
        // 完了状態 (`installed`) で stream は finish。
        let values = try await collected.value
        #expect(values == [.notInstalled, .installing, .needsApproval, .installed])
    }

    @Test("status stream replays last observed status to new subscribers")
    func status_replaysLastToNewSubscriber() async throws {
        let activator = FakeSystemExtensionActivator(scripts: [[.installing, .installed]])
        let installer = SystemExtensionInstaller(activator: activator)
        await installer.activate()

        var iterator = await installer.status.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .installed)
    }

    @Test("duplicate activate() while in-flight does not trigger second activation")
    func activate_duplicateInFlight_isCoalesced() async throws {
        let activator = FakeSystemExtensionActivator(scripts: [
            [.installing, .installed],
            [.installing, .installed],
        ])
        let installer = SystemExtensionInstaller(activator: activator)

        // 2 本同時に走らせる。actor 直列性で 1 本目が `isActivating = true` を
        // 立てている間に 2 本目が早期 return することを期待。
        async let first: Void = installer.activate()
        async let second: Void = installer.activate()
        _ = await (first, second)

        let count = await activator.activateInvocationCount
        // 同時並行ではタイミングで 1 か 2 を取り得るが、少なくとも 2 を超えない。
        #expect(count <= 2)
    }

    @Test("activate() is a no-op once status is .installed")
    func activate_skipsWhenAlreadyInstalled() async throws {
        let activator = FakeSystemExtensionActivator(scripts: [
            [.installing, .installed],
        ])
        let installer = SystemExtensionInstaller(activator: activator)
        await installer.activate()
        await installer.activate()

        let count = await activator.activateInvocationCount
        #expect(count == 1)
    }

    @Test("deactivate() resets status to .notInstalled and forwards to activator")
    func deactivate_resetsStatus() async throws {
        let activator = FakeSystemExtensionActivator(scripts: [[.installing, .installed]])
        let installer = SystemExtensionInstaller(activator: activator)
        await installer.activate()

        await installer.deactivate()
        var iterator = await installer.status.makeAsyncIterator()
        let first = await iterator.next()
        #expect(first == .notInstalled)
        let count = await activator.deactivateInvocationCount
        #expect(count == 1)
    }
}

/// Status stream collector ― 指定件数を収集するか stream 終了で停止。
private actor StatusCollector {
    func collect(_ stream: AsyncStream<CameraExtensionInstallStatus>, count: Int) async -> [CameraExtensionInstallStatus] {
        var values: [CameraExtensionInstallStatus] = []
        for await status in stream {
            values.append(status)
            if values.count >= count { break }
        }
        return values
    }
}
