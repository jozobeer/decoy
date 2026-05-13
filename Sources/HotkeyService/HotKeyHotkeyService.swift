import AppKit
import HotKey
import Domain

/// `HotKey`（soffes/HotKey）を使った `HotkeyService` の live 実装。
///
/// HotKey ライブラリは Carbon の `RegisterEventHotKey` をラップしている
/// ため、グローバルショートカットは **アクセシビリティ権限なし** で動作
/// する（NSEvent のグローバルモニタ系と違って `kAXTrustedCheckOptionPrompt`
/// を要求しない）。Decoy のメニューバー常駐前提との相性がよい。
///
/// 状態は `HotKey` インスタンスの配列で管理する。HotKey は ARC ベースの
/// lifecycle（参照が落ちると自動でアンレジスタ）なので、`unregisterAll`
/// は格納配列を空にするだけでよい。actor で状態を直列化し、`Sendable`
/// 境界も自然に整う。
public actor HotKeyHotkeyService {
    /// 登録ショートカットの bookkeeping。
    /// `KeyboardShortcut` をキーにすることで同一ショートカットの再登録は
    /// 上書き（後勝ち）になる ― port の契約に合わせている。
    private var registry: [KeyboardShortcut: HotKey] = [:]

    public init() {}
}

extension HotKeyHotkeyService: HotkeyService {
    public func register(
        _ shortcut: KeyboardShortcut,
        handler: @Sendable @escaping () async -> Void
    ) async {
        let key = Self.hotKeyKey(for: shortcut.key)
        let modifiers = Self.modifierFlags(for: shortcut.modifiers)
        let hotKey = HotKey(key: key, modifiers: modifiers)
        hotKey.keyDownHandler = {
            // HotKey の handler は main thread から呼ばれる。Sendable な
            // closure に actor の self を持ち込まず、Task を一段挟んで
            // ハンドラ側の async 文脈に橋渡しする。
            Task { await handler() }
        }
        registry[shortcut] = hotKey
    }

    public func unregisterAll() async {
        // HotKey 参照が消えるとライブラリ側が Carbon のホットキースロットを
        // 解放してくれる ― ARC が unregister のトリガになっている。
        registry.removeAll()
    }

    public var registeredCount: Int {
        registry.count
    }
}

extension HotKeyHotkeyService {
    /// Domain の `KeyboardShortcut.Key` を HotKey の `Key` enum に対応付ける。
    /// 表は全網羅 ― マッピング漏れがあるとそのキーが register できなくなる。
    /// `HotKeyHotkeyServiceMappingTests` が表の網羅を保証する。
    private static func hotKeyKey(for key: KeyboardShortcut.Key) -> Key {
        switch key {
        case .a: return .a
        case .b: return .b
        case .c: return .c
        case .d: return .d
        case .e: return .e
        case .f: return .f
        case .g: return .g
        case .h: return .h
        case .i: return .i
        case .j: return .j
        case .k: return .k
        case .l: return .l
        case .m: return .m
        case .n: return .n
        case .o: return .o
        case .p: return .p
        case .q: return .q
        case .r: return .r
        case .s: return .s
        case .t: return .t
        case .u: return .u
        case .v: return .v
        case .w: return .w
        case .x: return .x
        case .y: return .y
        case .z: return .z
        }
    }

    /// Domain の `Modifiers` を AppKit の `NSEvent.ModifierFlags` に変換する。
    /// HotKey は `[NSEvent.ModifierFlags]` 配列を受け取る API なので
    /// reduce で合成して 1 つの `NSEvent.ModifierFlags` を返す。
    private static func modifierFlags(for modifiers: KeyboardShortcut.Modifiers) -> NSEvent.ModifierFlags {
        let mapping: [(KeyboardShortcut.Modifiers, NSEvent.ModifierFlags)] = [
            (.command, .command),
            (.shift, .shift),
            (.option, .option),
            (.control, .control),
        ]
        return mapping
            .filter { modifiers.contains($0.0) }
            .map { $0.1 }
            .reduce(NSEvent.ModifierFlags()) { $0.union($1) }
    }
}
