# Development Best Practices

## Code Quality & Structure

- **400-line file limit**: Files should not exceed 400 lines, ideally under 100 lines
- **Library unification**: Unify libraries with the same functionality within a project
- **Type safety priority**: Prioritize type safety even in test code
- **Consistency with existing implementations**: When similar implementations
  exist, match their granularity (e.g., Repository, UseCase layers in backend).
  This makes code easy to compare and maintain
  - Maintain the same level of abstraction and file structure
  - Mirror existing patterns to ensure codebase consistency
  - If existing patterns are few and not well-refined, consider improving them
  - If many similar implementations already exist, align new code with them
- **Reuse existing code**: Prefer reusing existing implementations over creating
  similar or duplicate code

## Database & Performance Considerations

- **Avoid N+1 query problems**: Always use eager loading, batch queries, or
  data loader patterns. N+1 avoidance takes precedence over code reuse - if
  reusing a function causes N+1 queries, write a new batch-optimized
  implementation instead
  - Use JOIN queries or includes/preload directives in ORMs
  - Implement DataLoader pattern for GraphQL or similar APIs
  - Monitor and profile database queries in development
  - Review query patterns during code reviews

## Project & Workspace Management

- **Package separation by responsibility**: Packages should be divided into
  small units by responsibility
- **Dependency management**: Manage dependencies clearly and keep them to a minimum

## Testing Strategy

### Mock Strategy Selection Criteria

- **Prefer real classes**: Basic data structure classes
  - Reason: Improved test reliability, verification of actual API behavior
- **Prefer mocks**: Heavy objects, DOM operations, network communication classes

### Coverage-Ignored Modules

See `claude/rules/coverage-ignored-modules.md` — never put production
implementation in modules excluded from code coverage (codecov ignore,
jest `coveragePathIgnorePatterns`, etc.). Coverage-ignored modules are
reserved for protocols, test stubs, and one-line DI wiring. Real logic
belongs in covered modules so quality gates apply.

## File & Project Management

### File Movement & Refactoring Considerations

- **File movement/rename checklist**:
  1. Update import paths
  2. Update test mock paths
  3. Check CI/CD settings
  4. Update related documentation
- **Principle**: Don't underestimate the scope of change impact

## Tool & Library Management

### Version Upgrade Strategy

- **Gradual migration**: Handle breaking changes step by step
- **Configuration file compatibility check**: Syntax changes, default value
  changes, deprecated features
- **CI/CD setting synchronization**: Unify versions between local and CI environments

### Configuration File Schema

- **Always search for a `$schema` URL** when creating or editing JSON, YAML,
  or TOML configuration files (e.g., `tsconfig.json`, `package.json`,
  `settings.json` for tools)
- Check the tool's official documentation, GitHub repository, or
  [SchemaStore](https://www.schemastore.org/json/) for available schemas
- If a schema exists, add the `"$schema"` property at the top of the file
- This enables IDE validation, autocompletion, and catches typos early

### Linter & Formatter Settings

- **Active use of auto-fix**: Prioritize tool-based auto-fix over manual fixes
- **Consistency assurance**: Use unified settings across the entire project
