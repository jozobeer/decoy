/// Live-wiring helper. `OSSystemExtensionActivator` を組み合わせて
/// `SystemExtensionInstaller` actor を構築する。
///
/// Coverage note: SystemExtensions framework の live 結線のみで純粋ロジックを
/// 含まないため coverage 対象外 (`codecov.yml` ignore 済み)。
public extension SystemExtensionInstaller {
    static func live(bundleIdentifier: String = "beer.jozo.decoy.CameraExtension") -> SystemExtensionInstaller {
        SystemExtensionInstaller(activator: OSSystemExtensionActivator(bundleIdentifier: bundleIdentifier))
    }
}
