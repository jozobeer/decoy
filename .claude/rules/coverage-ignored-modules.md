# Coverage-Ignored Modules: No Implementation Allowed

**Never place production implementation code in modules that are excluded
from code coverage.** Coverage-ignored modules are reserved for wiring,
contracts, and stubs — putting real logic there lets bugs hide behind the
ignore rule.

## How to Identify Ignored Modules

Check the project's coverage config (most common):

- `codecov.yml` → `ignore:` list
- `.codecov.yml` → same
- SPM: look for `ignore` blocks referencing `Sources/<Module>/**`
- JS: `jest.config.js` `coveragePathIgnorePatterns`, `nyc` `exclude`
- Python: `.coveragerc` `omit`
- Rust: `tarpaulin` `exclude-files`, `cargo-llvm-cov` `--ignore-filename-regex`

Before adding code to any module, confirm it is **not** on that list. If
it is, the module is reserved for one of:

- Protocol / interface definitions (contract layer)
- Test stubs / `testValue` for DI frameworks
- Dependency injection wiring (just `liveValue = Foo()` one-liners)
- Type re-exports / module facades

## Why

A module excluded from coverage is effectively invisible to quality
gates. Implementation placed there:

- Ships without test enforcement — bugs land silently
- Bypasses the coverage threshold that applies to every other module
- Misleads reviewers: "coverage is green" no longer means what it says
- Creates a temptation to quietly move uncovered code there to hit CI targets

Coverage ignore is a scalpel for files that are structurally hard to
test (DI graphs, auto-generated code). It is not a shortcut to avoid
writing tests.

## Correct Pattern

When a protocol is defined in an ignored module (e.g. `Domain`) and
needs a live implementation:

1. Put the implementation in its **own covered module** (e.g.
   `Sources/SystemRandomSource/`, `Sources/FooProviderImpl/`)
2. The ignored DI module only holds the one-line `liveValue` wiring,
   importing the covered module
3. Add tests for the implementation module

```text
Sources/Domain/            # ignored — protocol + testValue stub
Sources/RandomSource/      # covered — SystemRandomSource
Sources/DependencyInjection/  # ignored — `liveValue = SystemRandomSource()`
Tests/RandomSourceTests/   # tests for the implementation
```

## Red Flags

- "I'll just drop this helper in Domain/DI, it's only 3 lines" — no
- "Coverage went up after I moved this file to the ignore list" — red flag
- Implementation file in ignored module that does anything beyond
  `static let liveValue = X()` — move it out

## `<Foo>+Live.swift` extension pattern

When an adapter target (e.g. `AVCameraSource`, `AVCameraPermission`,
`SystemExtensionInstaller`) has both **pure logic** and **OS-direct
wiring**, split them by file:

- `<Foo>.swift` — pure logic, covered by tests
- `<Foo>+Live.swift` — extension carrying only OS-direct wiring,
  `codecov.yml` で個別 ignore する

This keeps the testable portion under quality gates while excluding the
parts that can only be exercised on a real device.

### Rules for `<Foo>+Live.swift`

1. **Content limited to**:
   - `extension Foo` with a `static func live(...) -> Foo`
     (or `init(live:)`) that wires real OS handles into the adapter
   - Stateless wrapper structs that call OS API directly
   - Type-name shims (no behavior of their own)
2. **File size: 50 lines** — including doc comments. If you need more,
   the file is doing too much; extract the logic to the pure-logic file
3. **No logic branches**:
   - `if condition { do() } else { other() }` ❌
   - `switch enum { case .a: ...; case .b: ... }` ❌
4. **Guard-clause failure paths are OK**:
   - `guard let x = OSLookup() else { throw .deviceUnavailable }` ✅
   - `guard authorized else { throw .denied }` ✅
   - Their bodies must be `throw` or `return`, matching the global
     guard-clause rule
5. **No mutable state** (`var`) — these files only resolve OS handles
6. **File header**: open with `// COVERAGE: OS-direct wiring only ―
   `<file>` listed in codecov.yml ignore` so the next reader sees the
   contract immediately

### Current `+Live.swift` files (codecov.yml ignore 済み)

- `Sources/AVCameraSource/AVCameraSource+Live.swift`
- `Sources/AVCameraPermission/AVCameraPermission+Live.swift`
- `Sources/SystemExtensionInstaller/SystemExtensionInstaller+Live.swift`

If a `+Live.swift` outgrows these rules, that's a signal to extract the
logic into a covered file (testable function on the adapter type).
