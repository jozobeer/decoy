import Dependencies
import Domain
import HotkeyService

extension DependencyValues {
    public var hotkeyService: any HotkeyService {
        get { self[HotkeyServiceKey.self] }
        set { self[HotkeyServiceKey.self] = newValue }
    }
}

private enum HotkeyServiceKey: DependencyKey {
    static let liveValue: any HotkeyService = HotKeyHotkeyService()
    static var testValue: any HotkeyService {
        unimplemented(
            #"@Dependency(\.hotkeyService)"#,
            placeholder: HotKeyHotkeyService() as any HotkeyService
        )
    }
}
