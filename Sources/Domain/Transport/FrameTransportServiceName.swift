/// host (`MachPortFrameTransport`) と extension (`MachPortFrameReceiver`)
/// が握る Mach service name。launchd の bootstrap server を介して
/// `bootstrap_look_up` (host) と `bootstrap_check_in` (extension) が
/// この同じ string を頼りに同じ port に出会う ― wire format の前段に
/// 当たる識別子。
///
/// 名前は bundle id namespace に揃える ― OS と他アプリの service name
/// との衝突を避けるため。
public enum FrameTransportServiceName {
    public static let mach: String = "beer.jozo.decoy.frameTransport"
}
