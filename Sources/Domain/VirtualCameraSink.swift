import Dependencies

public protocol VirtualCameraSink: Sendable {
    func send(_ frame: Frame) async throws
}

public enum VirtualCameraSinkKey: TestDependencyKey {
    public static let testValue: any VirtualCameraSink = UnimplementedVirtualCameraSink()
}

extension DependencyValues {
    public var virtualCameraSink: any VirtualCameraSink {
        get { self[VirtualCameraSinkKey.self] }
        set { self[VirtualCameraSinkKey.self] = newValue }
    }
}

private struct UnimplementedVirtualCameraSink: VirtualCameraSink {
    func send(_ frame: Frame) async throws {
        reportIssue(#"@Dependency(\.virtualCameraSink)"#)
    }
}
