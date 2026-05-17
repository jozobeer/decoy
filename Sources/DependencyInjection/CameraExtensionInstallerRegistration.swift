import Dependencies
import Domain
import SystemExtensionInstaller

extension CameraExtensionInstallerKey: DependencyKey {
    public static let liveValue: any CameraExtensionInstaller = SystemExtensionInstaller.live()
}
