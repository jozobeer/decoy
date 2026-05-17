import Domain
import SystemExtensionInstaller

/// テスト用の `SystemExtensionActivator`。事前にスクリプトした
/// status 列を `activate()` ごとに新しい AsyncStream として吐き出す。
///
/// 呼び出し回数を `invocationCount` で検査可能。
public actor FakeSystemExtensionActivator {
    private var scripts: [[CameraExtensionInstallStatus]]
    public private(set) var activateInvocationCount = 0
    public private(set) var deactivateInvocationCount = 0
    public var deactivateError: Error?

    public init(scripts: [[CameraExtensionInstallStatus]]) {
        self.scripts = scripts
    }
}

extension FakeSystemExtensionActivator: SystemExtensionActivator {
    public func activate() -> AsyncStream<CameraExtensionInstallStatus> {
        activateInvocationCount += 1
        let script = scripts.isEmpty ? [] : scripts.removeFirst()
        return AsyncStream { continuation in
            for status in script {
                continuation.yield(status)
            }
            continuation.finish()
        }
    }

    public func deactivate() async throws {
        deactivateInvocationCount += 1
        if let error = deactivateError { throw error }
    }
}
