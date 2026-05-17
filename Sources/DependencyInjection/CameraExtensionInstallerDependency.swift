import Dependencies
import Domain
import InMemorySystemExtensionInstaller
import SystemExtensionInstaller

extension DependencyValues {
    public var cameraExtensionInstaller: any CameraExtensionInstaller {
        get { self[CameraExtensionInstallerKey.self] }
        set { self[CameraExtensionInstallerKey.self] = newValue }
    }
}

private enum CameraExtensionInstallerKey: DependencyKey {
    static let liveValue: any CameraExtensionInstaller = SystemExtensionInstaller.live()
    static var testValue: any CameraExtensionInstaller {
        unimplemented(
            #"@Dependency(\.cameraExtensionInstaller)"#,
            placeholder: AlwaysInstalledSystemExtensionInstaller() as any CameraExtensionInstaller
        )
    }
}
