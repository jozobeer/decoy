import Dependencies
import Domain
import HotkeyService

extension HotkeyServiceKey: DependencyKey {
    public static let liveValue: any HotkeyService = HotKeyHotkeyService()
}
