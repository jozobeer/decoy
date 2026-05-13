/// グローバルキーボードショートカットを Domain 層で記述するための値型。
///
/// HotKey / Carbon / AppKit など外部ライブラリの型に依存させない
/// ことで、adapter の入れ替えを許容する port を維持する。実装側
/// （`HotkeyService` の live 実装）でライブラリ固有のキー定数へ
/// マッピングする。
public struct KeyboardShortcut: Sendable, Hashable {
    public let key: Key
    public let modifiers: Modifiers

    public init(key: Key, modifiers: Modifiers) {
        self.key = key
        self.modifiers = modifiers
    }
}

public extension KeyboardShortcut {
    /// 物理キー識別子。アルファベットのみを定義する MVP スコープ。
    /// 文字種を増やすときは live 実装側のマッピング表を一緒に拡張する。
    enum Key: Sendable, Hashable {
        case a, b, c, d, e, f, g, h, i, j, k, l, m
        case n, o, p, q, r, s, t, u, v, w, x, y, z
    }

    /// 修飾キーの集合。`OptionSet` にしてあるので `[.command, .shift]`
    /// のように複数を素直に表現できる。
    struct Modifiers: OptionSet, Sendable, Hashable {
        public let rawValue: Int
        public init(rawValue: Int) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }
}
