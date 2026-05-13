import Testing
import Domain
@testable import HotkeyService

/// HotKey ライブラリは Carbon の `RegisterEventHotKey` をプロセス
/// グローバルな辞書 `[KeyCombo: HotKey]` で管理しているため、同一
/// プロセス内で同じ KeyCombo を 2 つ生成すると内部辞書が衝突して
/// クラッシュする。Swift Testing はデフォルトで suite 間も並列実行
/// するため、テスト全体を 1 つの suite に集約して `.serialized` で
/// 直列化する。各テストの末尾でも `unregisterAll()` を呼んで Carbon
/// 側のスロットを即座に解放する（actor の deinit に依存しない）。
@Suite("HotKeyHotkeyService", .serialized)
struct HotKeyHotkeyServiceTests {
    // Lifecycle 系で使う ⌘⇧+英字
    private static let cmdShiftR = KeyboardShortcut(key: .r, modifiers: [.command, .shift])
    private static let cmdShiftD = KeyboardShortcut(key: .d, modifiers: [.command, .shift])
    private static let cmdShiftL = KeyboardShortcut(key: .l, modifiers: [.command, .shift])
    private static let cmdShiftO = KeyboardShortcut(key: .o, modifiers: [.command, .shift])

    @Test func init_registeredCountIsZero() async {
        let service = HotKeyHotkeyService()
        let count = await service.registeredCount
        #expect(count == 0)
    }

    @Test func register_increasesRegisteredCount() async {
        let service = HotKeyHotkeyService()
        await service.register(Self.cmdShiftR, handler: {})
        let count = await service.registeredCount
        #expect(count == 1)
        await service.unregisterAll()
    }

    @Test func registerMultiple_eachCountsOnce() async {
        let service = HotKeyHotkeyService()
        await service.register(Self.cmdShiftR, handler: {})
        await service.register(Self.cmdShiftD, handler: {})
        await service.register(Self.cmdShiftL, handler: {})
        await service.register(Self.cmdShiftO, handler: {})
        let count = await service.registeredCount
        #expect(count == 4)
        await service.unregisterAll()
    }

    @Test func registerSameShortcutTwice_overwritesHandler() async {
        let service = HotKeyHotkeyService()
        await service.register(Self.cmdShiftR, handler: {})
        await service.register(Self.cmdShiftR, handler: {})
        let count = await service.registeredCount
        #expect(count == 1)
        await service.unregisterAll()
    }

    @Test func unregisterAll_resetsToZero() async {
        let service = HotKeyHotkeyService()
        await service.register(Self.cmdShiftR, handler: {})
        await service.register(Self.cmdShiftD, handler: {})
        await service.unregisterAll()
        let count = await service.registeredCount
        #expect(count == 0)
    }

    @Test func unregisterAll_whenEmpty_isNoop() async {
        let service = HotKeyHotkeyService()
        await service.unregisterAll()
        let count = await service.registeredCount
        #expect(count == 0)
    }

    @Test func registerAfterUnregister_worksAgain() async {
        let service = HotKeyHotkeyService()
        await service.register(Self.cmdShiftR, handler: {})
        await service.unregisterAll()
        await service.register(Self.cmdShiftD, handler: {})
        let count = await service.registeredCount
        #expect(count == 1)
        await service.unregisterAll()
    }

    /// 26 文字すべての Key → HotKey マッピングに穴がないことを保証する。
    /// 修飾キーは Lifecycle 系と被らないように ⌥⌃ を使う。
    @Test func allKeyboardShortcutKeys_haveHotKeyMapping() async {
        let allKeys: [KeyboardShortcut.Key] = [
            .a, .b, .c, .d, .e, .f, .g, .h, .i, .j, .k, .l, .m,
            .n, .o, .p, .q, .r, .s, .t, .u, .v, .w, .x, .y, .z,
        ]
        let service = HotKeyHotkeyService()
        for key in allKeys {
            let shortcut = KeyboardShortcut(key: key, modifiers: [.option, .control])
            await service.register(shortcut, handler: {})
        }
        let count = await service.registeredCount
        #expect(count == allKeys.count)
        await service.unregisterAll()
    }

    /// 異なる modifier 組合せは別ショートカットとして共存できる。
    @Test func allModifiers_combineWithoutCollision() async {
        let service = HotKeyHotkeyService()
        await service.register(KeyboardShortcut(key: .z, modifiers: [.option]), handler: {})
        await service.register(KeyboardShortcut(key: .z, modifiers: [.option, .control]), handler: {})
        await service.register(KeyboardShortcut(key: .z, modifiers: [.option, .command]), handler: {})
        await service.register(KeyboardShortcut(key: .z, modifiers: [.option, .shift]), handler: {})
        let count = await service.registeredCount
        #expect(count == 4)
        await service.unregisterAll()
    }
}
