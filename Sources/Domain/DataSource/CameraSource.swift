import Dependencies

/// カメラから連続的にフレームを取り出すための port。
///
/// 実装は以下の契約を満たすこと：
///
/// - `frames()` を呼ぶたびに、その時点以降のフレームを購読する `AsyncStream` を返す
///   （複数購読は実装に委ねるが、port としては「新しい購読ごとに新しい stream」を期待する）
/// - 各 `Frame.presentationTime` は **同一 stream 内で単調増加**（monotonic non-decreasing）
///   であること。Recorder はこの不変条件に依拠して clip duration を `last.pts - first.pts`
///   で算出するため、源流側でタイムスタンプの逆転を許してはならない
/// - stream は consumer の `Task` 取消に呼応して終端できることが望ましい
///   （Recorder は `Task.cancel()` で消費 Task を停止するため、stream を購読し続ける
///   実装は購読を抱え込み続けないこと）
public protocol CameraSource: Sendable {
    func frames() async -> AsyncStream<Frame>
}

public enum CameraSourceKey: TestDependencyKey {
    public static let testValue: any CameraSource = UnimplementedCameraSource()
}

extension DependencyValues {
    public var cameraSource: any CameraSource {
        get { self[CameraSourceKey.self] }
        set { self[CameraSourceKey.self] = newValue }
    }
}

private struct UnimplementedCameraSource: CameraSource {
    func frames() async -> AsyncStream<Frame> {
        reportIssue(#"@Dependency(\.cameraSource)"#)
        return AsyncStream { $0.finish() }
    }
}
