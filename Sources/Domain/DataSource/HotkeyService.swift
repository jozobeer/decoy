import Dependencies

/// グローバルキーボードショートカットを登録・解除する port。
///
/// 役割は「`KeyboardShortcut` が押されたら受け取ったハンドラを発火する」
/// ことだけ。`AppCommand` をディスパッチする責務は持たない ―
/// adapter 層（Decoy app）が register 時に渡すハンドラで `AppCommand`
/// を組み立て `AppCommandDispatcher` に流す。これにより
/// `HotkeyService` は `AppCommandDispatcher` への参照を持たず、テストや
/// adapter の入れ替えがしやすくなる。
///
/// 契約：
///
/// - `register(_:handler:)` は 1 つ以上のショートカットを登録する。
///   同じ `KeyboardShortcut` を二重登録した場合の挙動は実装に委ねるが、
///   live 実装は「後勝ち」が自然（古いハンドラは捨てる）。
/// - `unregisterAll()` は登録済みショートカットをすべて解除する。
///   アプリ終了時 / テスト後始末で呼ばれることを想定。
/// - ハンドラはキー押下のたびに発火する `@Sendable () async -> Void`
///   クロージャ。`async` を許すことで内部で `await dispatcher.dispatch(...)`
///   できるようにしている。
public protocol HotkeyService: Sendable {
    /// 1 つのショートカットに対応するハンドラを登録する。
    /// 既存登録は維持され、追加される。
    func register(_ shortcut: KeyboardShortcut, handler: @Sendable @escaping () async -> Void) async

    /// 登録済みのすべてのショートカットを解除する。
    func unregisterAll() async

    /// 現在登録されているショートカットの数。
    /// テストおよび lifecycle 検証のための観測点。
    var registeredCount: Int { get async }
}

public enum HotkeyServiceKey: TestDependencyKey {
    public static let testValue: any HotkeyService = UnimplementedHotkeyService()
}

extension DependencyValues {
    public var hotkeyService: any HotkeyService {
        get { self[HotkeyServiceKey.self] }
        set { self[HotkeyServiceKey.self] = newValue }
    }
}

private struct UnimplementedHotkeyService: HotkeyService {
    func register(_ shortcut: KeyboardShortcut, handler: @Sendable @escaping () async -> Void) async {
        reportIssue(#"@Dependency(\.hotkeyService)"#)
    }
    func unregisterAll() async {
        reportIssue(#"@Dependency(\.hotkeyService)"#)
    }
    var registeredCount: Int {
        get async {
            reportIssue(#"@Dependency(\.hotkeyService)"#)
            return 0
        }
    }
}
