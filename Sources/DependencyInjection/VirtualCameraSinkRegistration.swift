import CMIOVirtualCameraSink
import Dependencies
import Domain

extension VirtualCameraSinkKey: DependencyKey {
    // CMIOVirtualCameraSink を本実装として使う。transport は
    // `@Dependency(\.frameTransport)` から引く ― frameTransport を差し替えた
    // ときに sink にも伝播させるため、生成箇所をここで二重管理しない。
    // #43 stage 2 で frameTransport の liveValue が MachPortFrameTransport に
    // 変わると、何も触らずに sink が新しい transport を掴む。
    public static var liveValue: any VirtualCameraSink {
        @Dependency(\.frameTransport) var transport
        return CMIOVirtualCameraSink(transport: transport)
    }
}
