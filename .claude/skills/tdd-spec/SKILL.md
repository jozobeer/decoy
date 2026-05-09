---
name: tdd-spec
description: >
  TDD-style test-first development skill. Generates comprehensive test cases that serve as executable
  specifications before any implementation code is written. Use this skill whenever the user asks to
  write tests first, create test cases, do TDD, write specs as tests, or mentions "test-driven".
  Also trigger when the user says things like "add tests for this feature", "what should the tests
  look like", "spec out the behavior", or wants to define expected behavior before coding.
  Even if the user just describes a feature or function they want to build, suggest using this
  skill to define the spec as tests first.
allowed-tools:
  - Read(*)
  - Write(*)
  - Edit(*)
  - Glob(*)
  - Grep(*)
---

# TDD Spec — Tests as Specification

This skill treats tests as the single source of truth for behavior specification.
A well-written test suite should be readable as a requirements document — anyone
should be able to understand *what* the system does by reading the tests alone,
without looking at the implementation.

## Core Philosophy

Tests are not afterthoughts or safety nets. They are the **specification itself**.
Every test case answers the question: "What should this system do in this situation?"

This means:
- Test names read as behavioral statements, not implementation details
- Grouping reflects logical categories of behavior, not code structure
- Edge cases and error paths get the same attention as happy paths
- Properties (invariants that always hold) are tested alongside examples

## Workflow

### Step 1: Understand the Target

Before writing anything, understand what needs to be tested:

- Read the relevant source code, type definitions, or feature description
- Identify the public API surface (functions, methods, endpoints, components)
- Note the input domain: what types, ranges, shapes are valid?
- Note the output domain: what are the possible results, side effects, errors?
- Identify invariants — properties that should always hold regardless of input

If the user gives you a feature description without code, work from that. If there's
existing code, read it to extract the implicit spec.

### Step 2: Generate the Test Case List

Present a structured list of test cases organized by behavior category.
Do NOT write test code yet — this is the specification review step.

Use this format:

```
## [Target Name] — Test Specification

### Normal Behavior
- [descriptive behavioral statement]
- [descriptive behavioral statement]

### Boundary Conditions
- [edge case description]
- [edge case description]

### Error Handling
- [what happens with invalid input X]
- [what happens when dependency Y fails]

### Properties (Invariants)
- [property that always holds, e.g., "output length never exceeds input length"]
- [round-trip property, e.g., "encode then decode returns original"]
```

**Guidelines for test case naming:**
- Use natural language that describes behavior, not implementation
- Start with what the system does, not how: "returns empty array when no items match" not "filters array and checks length"
- Include the condition and expected outcome: "[when X] → [then Y]"
- Be specific enough that a test failure message tells you exactly what broke

**Coverage categories to always consider:**
1. **Normal behavior** — the happy path, typical inputs and outputs
2. **Boundary conditions** — empty inputs, single elements, maximum sizes, zero, negative numbers, unicode, whitespace
3. **Error handling** — invalid inputs, missing required fields, type mismatches, network failures, timeouts, permission errors
4. **State transitions** — if stateful, test each valid transition and reject invalid ones
5. **Concurrency** (if applicable) — race conditions, ordering guarantees
6. **Properties/Invariants** — things that must always be true regardless of input:
   - Idempotency: calling twice gives the same result
   - Round-trip: encode/decode, serialize/deserialize
   - Monotonicity: adding elements never decreases the count
   - Commutativity: order of inputs doesn't change result (where applicable)
   - No side effects: pure functions don't modify inputs

Wait for user confirmation before proceeding to Step 3.

### Step 2.5: Verify Red State

Before writing test code, mentally confirm that every test case in the list will fail
against the current codebase (or against no implementation at all). This is critical —
a test that passes before implementation is tautological and provides no specification value.

After writing the tests in Step 3, run the full test suite to confirm all new tests fail.
If any test passes unexpectedly, investigate:
- The test may be asserting something already implemented (redundant spec)
- The test may be tautological (always passes regardless of implementation)
- The assertion may be inverted or incomplete

Report any unexpected passes to the user before proceeding.

### Step 3: Write the Tests

After the user approves (or adjusts) the test case list, write the actual test code.

#### Language & Framework Detection

Detect the project's language and testing setup:
- Check existing test files for patterns and conventions
- Check package.json, Cargo.toml, Package.swift, build.gradle, pyproject.toml, etc.
- Match the existing test style (naming, grouping, assertion style)

If no existing tests exist, choose well-maintained, popular libraries:

| Language | Test Runner | Property Testing | Notes |
|----------|------------|-----------------|-------|
| TypeScript/JS | Vitest | fast-check | Vitest has native TypeScript, fast ESM support |
| Python | pytest | Hypothesis | Hypothesis is the gold standard for property testing |
| Rust | built-in (#[test]) | proptest | proptest has shrinking, strategies |
| Swift | Swift Testing | swift-testing macros | Use #expect, @Test, not XCTest for new projects |
| Go | testing | rapid | rapid is lightweight and well-maintained |
| Kotlin/Java | JUnit 5 + kotest | kotest-property | Kotest integrates property testing natively |

Before recommending a library you haven't verified recently, check its GitHub
repository to confirm it's actively maintained (recent commits, high star count).
When the project already uses a testing library, use that — don't introduce a new one
unless there's a clear benefit (e.g., adding property testing that didn't exist).

#### Test Structure

Organize tests to mirror the specification categories from Step 2.
Use `describe`/`context`/`it` (or language equivalent) nesting to create readable groupings.

```
describe("[Target]")
  describe("normal behavior")
    it("[behavioral statement from spec]")
  describe("boundary conditions")
    it("[edge case from spec]")
  describe("error handling")
    it("[error scenario from spec]")
  describe("properties")
    it("[invariant from spec]")
```

#### Writing Style

- Each test should be independently understandable — avoid shared mutable state
- Use the Arrange-Act-Assert (Given-When-Then) pattern
- Prefer explicit values over magic numbers — make test data tell a story
- For property tests, define generators that produce the full input domain
- Use descriptive variable names in tests: `expiredToken`, `emptyCart`, `userWithoutPermission`
- If a test needs complex setup, extract a well-named factory function rather than
  burying setup details in the test body

#### Parameterized Tests

When multiple test cases share the same structure but differ only in input/output values,
use parameterized tests (table-driven tests) instead of duplicating test bodies.
This makes the specification denser and easier to extend.

```typescript
// Vitest example
it.each([
  { input: "",        expected: true,  scenario: "empty string" },
  { input: "  ",      expected: true,  scenario: "whitespace only" },
  { input: "hello",   expected: false, scenario: "non-empty string" },
])("isBlank returns $expected for $scenario", ({ input, expected }) => {
  expect(isBlank(input)).toBe(expected)
})
```

```python
# pytest example
@pytest.mark.parametrize("input_val,expected,scenario", [
    ("", True, "empty string"),
    ("  ", True, "whitespace only"),
    ("hello", False, "non-empty string"),
])
def test_is_blank(input_val, expected, scenario):
    assert is_blank(input_val) == expected
```

Use parameterized tests for boundary value exploration and equivalence class coverage.
Keep each table row self-documenting — include a `scenario` or description field so
failures identify which case broke without reading the data.

#### Property Testing Integration

For every function, ask: "What properties should always hold?"

Common property patterns:
- **Round-trip**: `decode(encode(x)) === x`
- **Idempotency**: `f(f(x)) === f(x)`
- **Invariant preservation**: `sort(xs).length === xs.length`
- **Commutativity**: `merge(a, b) === merge(b, a)`
- **Associativity**: `combine(combine(a, b), c) === combine(a, combine(b, c))`
- **Oracle**: compare your implementation against a known-correct but slower reference

Write property tests alongside example-based tests — they complement each other.
Example tests are readable specifications; property tests catch unexpected edge cases.

### Step 3.5: Parallel Test Generation with Agent Teams

When there are multiple test categories or multiple targets, use subagents
(subagent_type: `test-generator`) to generate tests in parallel. This dramatically
reduces wait time for comprehensive test suites.

**When to parallelize:**
- Multiple independent targets (e.g., 3 functions, 2 API endpoints)
- A single target with many test categories that don't share setup logic
- Property tests can always run in parallel with example-based tests

**Parallelization strategy:**

After the user approves the test case list in Step 2, split the work by category
or by target — whichever produces more independent chunks.

**Option A — Split by target** (when testing multiple functions/modules):
Spawn one agent per target. Each agent receives:
- The approved test case list for its target
- The source code or type definitions it needs
- The project's testing conventions (framework, style, file naming)
- Instructions to write a complete test file for that target

**Option B — Split by category** (when testing one large target):
Spawn agents for independent categories. For example:
- Agent 1: Normal behavior + boundary conditions (these often share setup)
- Agent 2: Error handling (independent — different inputs, different assertions)
- Agent 3: Property tests (independent — different assertion style entirely)

**Agent prompt template:**
```
You are writing tests as part of a TDD specification workflow.

Target: [function/module name and signature]
Source: [path to source or type definitions]
Test framework: [detected framework]
Property testing library: [if applicable]
Approved test cases for your scope:
[subset of test case list from Step 2]

Write the test code for these cases only. Follow these conventions:
- [project-specific conventions detected in Step 3]
- Tests are specifications — names must read as behavioral statements
- Use Arrange-Act-Assert pattern
- Include assertion messages that explain what broke

Output: the complete test code for your assigned scope.
```

**After all agents complete:**
1. Collect outputs from all agents
2. Merge into a single test file (or keep separate files if that fits the project structure)
3. Resolve any shared imports, helpers, or factory functions — deduplicate
4. Ensure consistent style across all sections
5. Run the merged tests to verify they compile and the structure is sound

If the test suite is small enough (roughly under 10 test cases for a single target),
skip parallelization and write everything inline — the overhead isn't worth it.

### Step 4: Review the Output

After writing tests, do a self-check:
- Can someone unfamiliar with the code read these tests and understand the spec?
- Are error messages clear when a test fails? (assertion messages, test names)
- Is there redundancy? (same behavior tested in multiple places without reason)
- Are property generators constrained appropriately? (not too broad, not too narrow)
- Did you cover all categories from Step 2?

## Next Step: Implementation

After the test suite is written and verified to be in Red state (all tests failing),
the natural next step is implementation. Use `/tdd-impl` to incrementally implement
code that passes these tests one by one, following the Red-Green-Refactor cycle.

The tdd-impl skill treats the tests created here as the authoritative specification
and will not modify them unless they contain genuine errors. If tdd-impl discovers
emergent properties during implementation, it will propose adding new tests back
into this spec — closing the feedback loop.

## Anti-Patterns to Avoid

- Testing implementation details (internal method calls, private state)
- Test names that describe code: "calls processData with correct args"
- Copy-pasting test bodies with minor variations — use parameterized tests instead
- Mocking everything — test real behavior where feasible, mock at boundaries
- Tests that pass regardless of implementation (tautological assertions)
- Overly broad property generators that make tests slow or flaky
