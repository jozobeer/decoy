# Git Workflow & Conventions

> プロジェクト固有のルールは各リポの `CONTRIBUTING.md` で明示する。
> このファイルは Repo-Forge から雛形コピーされた汎用ガイド ― 各リポで自由に上書きしてよい。

## Project-Specific Rules Take Precedence

- **Always check for project-level git conventions first** — branch naming,
  commit message format, merge strategy, PR workflow, etc.
- Sources to check: project CLAUDE.md, CONTRIBUTING.md, `.github/` templates,
  linter configs (commitlint, etc.), and existing git history patterns
- When project rules exist, follow them exactly — do not override with
  personal defaults
- When no project rules exist and the project is established, apply the
  defaults defined in this file
- **For new projects**: Ask the user about branch strategy, commit conventions,
  and merge policy before assuming defaults. If the project's nature suggests
  a particular strategy (e.g., trunk-based for small teams, Git Flow for
  release-driven projects), proactively propose it with reasoning

## Feature Branch Development (Stacked PRs)

- Large features may use a **development branch** (e.g., `feature/xxx/dev`)
  branched from main, with sub-branches merging into it
- When creating the dev branch, use `git commit --allow-empty` to enable
  creating a draft PR toward main before any real diff exists
- Sub-branches create PRs targeting the dev branch, not main

### CRITICAL: Never Merge or Modify Branches to Force PR Creation

- **NEVER merge branches, close PRs, or modify branch state** just because
  a PR cannot be created due to missing diff
- If there is no diff between branches, **stop and ask the user** how to proceed
- Acceptable solutions: empty commit, wait for sub-branch merges, etc.
- **This applies to ALL situations** where PR creation fails — never take
  destructive or irreversible actions as a workaround without explicit
  user approval

## Safety Checks

- **Verify current branch before operations** — before commit, push, or merge,
  always confirm the current branch matches the intended target
- **Never amend published commits** — if a commit has been pushed, create a
  new commit instead. Amending requires force push and risks overwriting
  others' work
- **Branch deletion requires user confirmation** — even after merge, always
  ask before deleting any branch

## Commit Discipline

- **One logical change per commit** — do not mix refactoring, formatting,
  and feature changes in a single commit
- **Rebase vs merge** — follow project conventions. When no convention exists,
  default to merge commits for feature branches (preserves context) and
  ask the user if they prefer rebase

## Git Worktree Utilization

- **CRITICAL: Subagents must NEVER switch branches.** `git checkout` and
  `git switch` change the working tree for ALL concurrent agents. Instead,
  use `isolation: "worktree"` when spawning, or create a worktree manually.
  When spawning any subagent that needs a different branch, always include
  this instruction in the prompt: "Do not switch branches. Use worktrees."
- **Purpose**: Efficiently switch between branches for reviews or code inspection
- **Location**: Checkout under `.worktrees/` directory
- **Important**: Add `.worktrees/` to `.gitignore` (if not already included)
- **Usage examples**:

  ```bash
  # Create new worktree
  git worktree add .worktrees/feature-branch origin/feature-branch

  # Reuse existing worktree
  cd .worktrees/existing-branch
  git pull
  ```

- **Operational guidelines**:
  - Multiple worktrees can be maintained simultaneously
  - No need to delete after work (reuse recommended)
  - Actively use for PR reviews and code comparisons

## PR Description Guidelines

- **Accuracy focus**: Accurately reflect actual changes (distinguish between
  new creation and migration)
- **Background explanation**: Clearly state reasons for architectural changes
- **Breaking changes declaration**: Clearly state deleted classes or changed structures
- **TODO items**: Include deployment adjustments and future required tasks
- **No Claude Code signature**: Do not include "Generated with Claude Code"
  in PR descriptions

## GitHub CLI Usage

- **Private repository access**: Use `gh` command instead of direct URL
  access for private repos
  - Use `gh api` for API endpoints
  - Use `gh repo view` for repository information
  - Use `gh pr view` or `gh issue view` for specific resources
- **Always use `--paginate` with `gh api`** when fetching lists (comments,
  PRs, issues, reviews, etc.). The default page size is 30 — without
  `--paginate`, items beyond the first page are silently dropped

## Cross-Repo Issue Linking

When creating issues that relate to the same topic across multiple
repositories, always add cross-references using `owner/repo#123` format
in the issue body. This is common when branch naming requires an issue
number per repo. Link bidirectionally — update the existing issue to
reference the new one, and include the reference in the new issue.

**Working outside the current repo:** When the user works on a repo
different from the current working directory, the two repos are often
related (e.g., backend + frontend, API + client). When creating issues or
PRs in the other repo, check whether they relate to existing issues/PRs
in the current repo and cross-link them. This applies to:
- Issues created via `gh issue create --repo other/repo`
- PRs created via `gh pr create --repo other/repo`
- Review comments that reference work in the current repo

Always think: "Does this belong in both repos?" If yes, link.

## GitHub Markdown Conventions

See `claude/rules/github-markdown.md` for conventions used in issue
bodies, PR descriptions, review comments, replies, and release notes —
covers shields.io badges, mojiemoji stamps, sanitizer-safe HTML, and
`<details>` folding.
