# Code Philosophy & Standards

## Core Principles

- Functional programming over object-oriented approaches
- Immutability and pure functions preferred
- Minimize variables - use function chains and direct returns instead of intermediate variables; use `const` only when necessary, never `let`
- Small, focused functions (under 100 lines ideal)
- Clean architecture with loose coupling
- Emphasis on readability and maintainability
- Use modern language features actively - leverage the latest syntax and features available in the project's language version (especially Swift, which evolves rapidly). This helps engineers learn practical use cases for new features

## Strict Single Responsibility Principle

- **One function, one purpose** - Never give a function multiple responsibilities
- **Function composability** - Build complex logic by composing small,
  single-purpose functions
- **Testability first** - Single-purpose functions make tests simple and clear

## If Statement Guidelines

**If statements are for guard clauses only** - use for early exits, never for executing logic. Use language-idiomatic constructs when available (e.g., `guard` in Swift, `unless` in Ruby). The body must be one of:

- `return value`
- `return`
- `throw`

```typescript
// Good - guard clauses
if (!isValid(name)) throw new Error(`Invalid: ${name}`);
if (isEmpty(data)) return defaultValue;
if (done) return;

// Bad - executing logic
if (condition) doSomething();
if (condition) {
    doSomething();
    doAnotherThing();
}
```

## Loop Guidelines

**Prefer declarative iteration over imperative loops.** Use `map`, `filter`, `reduce`, `flatMap`, etc. instead of `for`/`while` loops. This eliminates mutable loop variables and intermediate state.

```typescript
// Good - declarative
const results = items.map(transform).filter(isValid);
const total = values.reduce((sum, v) => sum + v, 0);

// Avoid - imperative
const results = [];
for (const item of items) {
    const transformed = transform(item);
    if (isValid(transformed)) results.push(transformed);
}
```

**Performance exception for reduce:** When accumulating into large collections, use a mutable accumulator within the reduce scope (like Swift's `reduce(into:)`) to avoid repeated copying:

```typescript
// Acceptable for performance
const grouped = items.reduce((acc, item) => {
    (acc[item.key] ??= []).push(item);
    return acc;
}, {} as Record<string, Item[]>);
```

Prefer immutability when performance is not a concern.

**Recursion as an alternative:** Recursive functions are also preferred over imperative loops. When the language supports tail call optimization (TCO), write tail-recursive functions to avoid stack overflow:

```typescript
// Tail-recursive (TCO-friendly)
const sum = (nums: number[], acc = 0): number =>
    nums.length === 0 ? acc : sum(nums.slice(1), acc + nums[0]);

// Not tail-recursive (stack may overflow)
const sum = (nums: number[]): number =>
    nums.length === 0 ? 0 : nums[0] + sum(nums.slice(1));
```

## Function Naming Guidelines

**Avoid verbs unless the primary purpose is a side effect.** Functions that
compute and return values are expressions — name them for what they evaluate
to, not what they do.

- **Nouns / adjectives / past participles** for pure functions:
  `sorted()`, `resolved()`, `encoded()`, `info`, `resolvedMetadata`
- **Verbs** only when the caller wants the side effect, not the return value:
  `save()`, `print()`, `send()`, `delete()`
- **`build` / `make` / `create`** reserved for Builder pattern (method
  chaining / mutating accumulation) or factory methods with side effects:
  `makeIterator()`, `URLRequest.build()`

```swift
// Good — past participle: describes the result, not an action
func washedText(_ raw: String) -> String
func resolvedMetadata(track: Track) async -> (String, String, [Track])
func encoded(_ data: Data) -> String
var info: NowPlayingInfo { get async { ... } }

// Bad — imperative verb implies side effect, but there is none
func washText(_ raw: String) -> String
func buildInfo() async -> NowPlayingInfo
func resolveMetadata(track: Track) async -> (String, String, [Track])

// Good — verb: caller wants the side effect
func save(_ record: Record) throws
func notify(_ user: User, message: String)
```

## Quality Standards

- Apply functional programming principles consistently
- Focus on architecture, performance, and security
- Provide constructive feedback with specific examples
- Use gentle but thorough review approach
