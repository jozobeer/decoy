# Swift Conventions

## Protocol Conformance via Extension

**Declare protocol conformance in a separate extension, not on the struct/class
declaration itself.** This keeps the type declaration focused on stored
properties and init, while protocol implementations are grouped in labeled
extensions.

```swift
// Good — conformance separated from declaration
public struct ServiceHandlerImpl {
    public init() {}
    private let label = "com.example.app"
}

extension ServiceHandlerImpl: ServiceHandler {
    public func install() -> ServiceInstallResult { ... }
    public func uninstall() -> ServiceUninstallResult { ... }
}

// Bad — conformance mixed into declaration
public struct ServiceHandlerImpl: ServiceHandler {
    public init() {}
    private let label = "com.example.app"
    public func install() -> ServiceInstallResult { ... }
    public func uninstall() -> ServiceUninstallResult { ... }
}
```

Benefits:
- Type declaration is a quick summary of stored state
- Protocol implementations are visually grouped and can be collapsed
- Multiple protocol conformances each get their own extension
- Compiler ensures the type as a whole satisfies every protocol requirement (requirements may be split across extensions, but the union must be complete)

## Computed Property vs Function

**Prefer computed properties over zero-argument functions when there are no side
effects and no expensive computation.** A value derived from existing state
without mutating anything is a property, not an action.

```swift
// Good — computed property: no side effects, lightweight lookup
var existingConfigPath: String? { findConfigFile()?.path }
var isLocked: Bool { /* flock check */ }

// Bad — function for the same purpose
func existingConfigPath() -> String? { findConfigFile()?.path }
func getVersion() -> String { bundle.version }

// Good — function: has side effects or expensive computation
func acquire() -> Bool { /* opens file, acquires flock, writes PID */ }
func fetchNowPlaying() async -> NowPlaying? { /* network/IPC call */ }
```

When adding a member to a protocol, ask: "Does calling this change anything?"
If not, it should be a `var … { get }`.

## Access Control in Extensions

**Prefer `private` over `fileprivate` in extensions whenever the symbol is
only used within the same type.** Since Swift 4, `private` declared in a
type or its same-file extensions is visible to all same-file extensions of
that **same type** — which is usually the scope you actually want. Use
`fileprivate` only when access from a *different* type in the same file is
required.

| modifier | scope |
|---|---|
| `private` | enclosing declaration ＋ same-file extensions of that **same type** |
| `fileprivate` | the entire file (any declaration) |

```swift
// Good
extension Foo {
    private func helper() { ... }
}

// Unnecessary
extension Foo {
    fileprivate func helper() { ... }
}
```

## Clock Injection for Testability

**Never use `Date()`, `Date.now`, `Timer.scheduledTimer`, or `ContinuousClock.now`
directly.** Inject a clock via `@Dependency(\.continuousClock)` (from
swift-dependencies) and use it for all time-dependent operations. In tests,
use `ImmediateClock` to make time pass instantly.

```swift
// Good — injectable clock
@Dependency(\.continuousClock) private var clock

func elapsedTime(for np: NowPlaying) -> TimeInterval? {
    guard let base = np.rawElapsed, let ts = np.timestamp else { return base }
    return base + np.playbackRate * clock.now.duration(to: .now).seconds
}

// Bad — hard-coded Date()
func elapsedTime(for np: NowPlaying) -> TimeInterval? {
    guard let base = np.rawElapsed, let ts = np.timestamp else { return base }
    return base + np.playbackRate * Date().timeIntervalSince(ts)
}
```

This applies to:
- `Task.sleep` → `clock.sleep`
- `Date()` / `Date.now` → `clock.now`
- `Timer.scheduledTimer` → async loop with `clock.sleep`
- `ContinuousClock.now` for measurements → injected clock

In tests:

```swift
let model = withDependencies {
    $0.continuousClock = ImmediateClock()
} operation: {
    MyModel()
}
// All sleeps and time checks resolve instantly
```

## Entity Module — Pure Data Only

**Entity types must contain zero logic.** No computed properties with
conditional logic, no init with parsing, no static factory methods with
branching. Entity is pure data: stored properties, Codable/Sendable/Equatable
conformance, and memberwise init only.

If you find logic in Entity (e.g. computed properties that branch, parsing
helpers, factory methods with conditions), move it to the appropriate
implementation module (UseCase, Presenter, etc.).

Consequence: **Entity requires no tests.** If Entity needs tests, that's a
signal that logic has leaked in and should be extracted.

## Force Unwrap

The Repo-Forge 共通原則「強制 unwrap 禁止」を Swift では以下に読み替える：

- `!` （後置 force unwrap）禁止
- `try!` 禁止 — `do/catch` または `try?` で扱う
- `as!` 禁止 — `as?` ＋ guard で安全な分岐に
- IUO（`var x: Foo!`）禁止 — `Foo?` で表現してアンラップ箇所で意図を示す

テストも同様。`!` を書いた瞬間、それは「絶対に nil でない」と神を演じている。
