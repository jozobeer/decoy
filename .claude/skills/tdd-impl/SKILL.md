---
name: tdd-impl
description: >
  TDD implementation skill — takes existing tests and incrementally implements code to make them pass.
  Tests are treated as the specification and must not be modified unless they misrepresent the intended
  behavior. Use this skill when the user has tests written (by tdd-spec or manually) and wants to
  implement the code, when the user says "make these tests pass", "implement this", "green phase",
  "write the implementation for these tests", or when there are failing tests that need implementation.
  Also trigger when the user has a test file open and asks to write the corresponding source code.
allowed-tools:
  - Read(*)
  - Write(*)
  - Edit(*)
  - Glob(*)
  - Grep(*)
  - Bash
---

# TDD Impl — Test-Driven Implementation

This skill implements code to satisfy existing tests, treating tests as the authoritative
specification. The workflow is incremental: pass one test at a time, verify intent with the
user, and refactor continuously.

## Core Principle: Tests Are Sacred

Tests represent the agreed-upon specification. They are not obstacles to work around —
they are the definition of correct behavior.

**When tests fail, the implementation is wrong — not the tests.**

The only legitimate reasons to modify a test:
- The test misrepresents the intended specification (a spec bug, not a code bug)
- The test contains a coding error (wrong assertion value, typo in setup)
- The test contradicts another test, revealing an inconsistency in the spec

When you suspect a test is wrong, stop and ask the user. Explain what the test expects,
what you believe the intended behavior should be, and why you think there's a discrepancy.
Never silently modify a test to make your implementation work.

## Workflow

### Step 0: Understand the Test Suite

Before writing any implementation:

1. Read all test files related to the target
2. Build a mental model of the specification by analyzing:
   - What behaviors are tested (the "what")
   - What inputs and outputs are expected (the contract)
   - What error conditions are covered (the boundaries)
   - What properties/invariants are asserted (the guarantees)
3. Identify the test execution order — which tests are foundational and which
   build on earlier behavior
4. Detect the project's language, framework, and testing setup
5. Detect the test runner command (see "Test Runner Detection" below)

Present a brief summary to the user:
```
## Implementation Plan for [Target]

Tests define [N] behaviors across [M] categories:
1. [Category]: [brief description] — [count] tests
2. [Category]: [brief description] — [count] tests
...

Proposed implementation order:
1. [test name] — [why this first: foundational type, core logic, etc.]
2. [test name] — [builds on #1 because...]
...

Detected setup: [language], [test framework], [relevant project conventions]
```

Wait for user confirmation before proceeding.

### Step 1: Red — Verify the Test Fails

Before implementing anything, run the target test to confirm it fails.
This is the "Red" in Red-Green-Refactor. It serves two purposes:
- Confirms the test is actually testing something (not tautologically passing)
- Establishes the baseline failure message you're trying to resolve

Report the failure to the user:
```
Running: [test name]
Status: FAIL (expected)
Error: [failure message]
→ This test expects [behavioral description]. Implementing now.
```

If a test unexpectedly passes before implementation, flag it — something is wrong
(either the test is tautological, or existing code already covers this behavior).

### Step 2: Green — Minimal Implementation

Write the minimum code necessary to make the current test pass.
"Minimum" means:
- No speculative features beyond what the test requires
- No premature abstractions or generalizations
- Simple, direct code that satisfies exactly the assertion

This is intentionally naive. The refactor step comes next. Resist the temptation
to write the "final" version immediately — that skips the learning that TDD provides.

After writing the implementation, run the test:
- **Pass**: Report success, move to Step 3
- **Fail**: Analyze the failure, adjust the implementation, re-run
  - If the failure suggests a spec ambiguity, ask the user before proceeding

Also run all previously passing tests to check for regressions:
- **All pass**: Good, continue
- **Regression**: Fix without breaking the new test. If impossible, this reveals
  a design tension — discuss with the user

### Step 3: Refactor — Improve Without Changing Behavior

After Green, look for opportunities to improve the code while keeping all tests passing.

Apply the project's established code conventions and style. Check for:
- CLAUDE.md or project documentation that defines code philosophy
- Existing codebase patterns (naming, structure, abstraction level)
- Linter/formatter configuration (.eslintrc, .prettierrc, rustfmt.toml, etc.)

Follow whatever conventions the project already uses. If no conventions exist,
apply general clean code principles: small functions, clear naming, minimal duplication.

After refactoring, run all tests again to confirm nothing broke.

Only report the refactoring if it's substantive. Minor cleanups (renaming a variable,
reordering lines) don't need user confirmation.

### Step 4: Repeat

Move to the next test in the planned order. Return to Step 1.

At natural breakpoints (after completing a category of tests, or every 3-5 tests),
pause and summarize progress:
```
## Progress: [X/N] tests passing

Completed:
- ✓ [category]: [what was implemented]

Next up:
- [category]: [what comes next]

Any concerns or direction changes before continuing?
```

### Step 5: Final Review

After all tests pass, do a holistic review:

1. Run the complete test suite one final time
2. Review the implementation against the full specification:
   - Does the code structure reflect the behavioral categories from the tests?
   - Are there implicit behaviors the tests assume but don't directly assert?
   - Is the public API clean and consistent?
3. Check for remaining refactoring opportunities now that the full picture is visible
4. Report the final state to the user

### Step 6: Discover Emergent Properties

Implementation often reveals properties that weren't part of the original specification
but naturally emerge from the design. These are valuable — they strengthen the spec and
catch future regressions in behaviors the original tests didn't anticipate.

After all tests pass and the implementation is stable, analyze the code for emergent properties:

**What to look for:**
- **Algebraic properties**: Does the implementation happen to be commutative, associative,
  or idempotent? If `merge(a, b)` always equals `merge(b, a)`, that's worth specifying.
- **Invariant preservation**: Does the output always satisfy certain constraints?
  (e.g., a sort function preserves length, a filter never adds elements)
- **Round-trip guarantees**: If you have encode/decode, serialize/deserialize pairs,
  does round-tripping always restore the original?
- **Monotonicity**: Does adding input always increase (or never decrease) the output?
- **Null/identity behaviors**: Does the function have a natural identity element?
  (e.g., `merge(x, empty) === x`)
- **Error boundary completeness**: Are there input classes that the tests don't cover
  but the implementation handles (or should handle)?
- **Performance characteristics**: Does the implementation have implicit complexity
  guarantees worth documenting as tests? (e.g., O(n) not O(n^2))

**How to present discovered properties:**

```
## Emergent Properties Discovered

The implementation reveals these properties not currently in the spec:

1. **Idempotency**: `normalize(normalize(x))` always equals `normalize(x)`
   → This falls out naturally from the implementation. Worth specifying?

2. **Empty input identity**: `merge(items, [])` returns items unchanged
   → Currently untested. Should this be guaranteed behavior?

3. **Order independence**: `process(a, b)` produces the same result as `process(b, a)`
   → Coincidental in current implementation, but useful if guaranteed.

For each property:
- [Add to spec] — Add a property test to lock this in as guaranteed behavior
- [Document only] — Note it but don't test (implementation detail, may change)
- [Skip] — Not worth specifying
```

**User decides for each property:**
- **Add to spec**: Use `/tdd-spec` to write property-based tests for the discovered
  properties. This feeds back into the spec — the specification grows from what we
  learned during implementation. The new tests become part of the living spec.
- **Document only**: Add a code comment noting the property without a test.
  This signals to future developers that it's a known characteristic but not a guarantee.
- **Skip**: Move on. Not every emergent property deserves formalization.

This step closes the TDD feedback loop: `/tdd-spec` → `/tdd-impl` → `/tdd-spec`.
The spec is a living document that grows richer as understanding deepens.

## Parallel Implementation with Agent Teams

When the test suite covers multiple independent targets or clearly separable modules,
use subagents to implement them in parallel.

**Independence test**: Two implementation chunks are independent when:
- They don't share mutable state
- They don't call each other's functions
- Their tests don't share setup that would change based on implementation

**When to parallelize:**
- Multiple independent modules/files to implement (e.g., UserService and EmailService)
- Utility functions that don't depend on each other
- After Step 0, when the implementation plan reveals natural boundaries

**When NOT to parallelize:**
- Tests within a single module that build on each other incrementally
- When later tests depend on design decisions from earlier ones
- When the user wants to review each step (the whole point of incremental TDD)

**Parallel strategy:**

After user approves the implementation plan in Step 0, identify independent groups:

```
Group A (Agent 1): [Module X] — tests 1-4 (self-contained)
Group B (Agent 2): [Module Y] — tests 5-8 (self-contained)
Group C (main): [Module Z] — tests 9-12 (depends on A and B, done after merge)
```

Each agent receives:
- The test file(s) for its group
- Any shared type definitions or interfaces
- The project's code conventions
- Instructions to follow the Red-Green-Refactor cycle within its group

**Agent prompt template:**
```
You are implementing code to pass a set of tests using TDD methodology.

Tests are the specification — do not modify them unless they contain errors.
Follow Red-Green-Refactor for each test in order.

Test file: [path]
Tests to implement (in order): [list]
Shared types/interfaces: [paths or inline definitions]
Project conventions: [language, style, patterns]

For each test:
1. Run it to confirm failure (Red)
2. Write minimal code to pass (Green)
3. Refactor while keeping all tests green

Output: the implementation file(s) with all assigned tests passing.
Report any tests you believe contain specification errors (do NOT fix them).
```

**After agents complete:**
1. Collect implementations from all agents
2. Run the full test suite to catch integration issues
3. Resolve any conflicts in shared types or interfaces
4. Proceed with dependent groups (Group C in the example above)
5. Report the merged result to the user

## Handling Spec Ambiguities

During implementation, you may discover that tests don't fully specify behavior
for certain inputs or edge cases. When this happens:

1. **Identify the gap**: "The tests specify behavior for non-empty lists but not for empty lists"
2. **Propose**: Suggest what the behavior should be based on the existing spec's patterns
3. **Ask**: Let the user decide — they may want to add a test first (back to tdd-spec)
4. **Implement**: Only after the user confirms the expected behavior

This back-and-forth between spec and implementation is the essence of TDD.
It's not a flaw in the process — it's the process working correctly.

## Handling Test Errors

If you encounter a test that appears to be incorrect:

1. **Do not modify the test**
2. Explain what the test asserts and why you believe it's wrong:
   ```
   Test: "returns -1 for empty array"
   The test asserts: indexOf([], 5) === -1
   Concern: Other tests treat empty array as throwing an error,
   which contradicts this assertion. Which behavior is intended?
   ```
3. Wait for the user to decide:
   - Fix the test (spec correction)
   - Fix your understanding (you misread the spec)
   - Accept both behaviors (different contexts)

## Test Runner Detection

Detect how to run tests before starting the Red-Green-Refactor cycle.
Check these sources in order (first match wins):

| Signal | Test Command |
|--------|-------------|
| `package.json` has `scripts.test` | `npm test` (or the specific command) |
| `package.json` has `vitest`/`jest` as dep | `npx vitest run` / `npx jest` |
| `Makefile` has `test` target | `make test` |
| `Cargo.toml` exists | `cargo test` |
| `Package.swift` exists | `swift test` |
| `go.mod` exists | `go test ./...` |
| `pyproject.toml` / `setup.cfg` with pytest | `pytest` |
| `build.gradle` / `build.gradle.kts` | `./gradlew test` |

For running a single test (needed in Step 1), detect the framework's filter syntax:
- Vitest/Jest: `--testNamePattern "test name"` or `-t "test name"`
- pytest: `-k "test_name"`
- cargo: `cargo test test_name`
- swift: `swift test --filter "TestClass/testName"`
- go: `-run "TestName"`

Include the detected test command in the implementation plan (Step 0) so the user
can verify it's correct before you start running tests.

## Anti-Patterns

- Writing the full implementation before running any tests (skipping Red)
- Modifying tests to match your implementation instead of the reverse
- Implementing more than what the current test requires (speculative coding)
- Skipping the Refactor step to "save time" (technical debt accumulates fast)
- Ignoring regression failures ("I'll fix it later")
- Parallelizing tests that have sequential dependencies
