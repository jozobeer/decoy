# Contributing to Decoy

このリポは [Repo-Forge](https://github.com/jozobeer/repo-forge) から scaffold された standalone プロダクト。
Repo-Forge とは独立しており、自分のペースで進化させてよい。

## Before you start

作業を始める前に必ず読むもの：

1. [`README.md`](README.md) — Dream とアーキテクチャの概要
2. [`.claude/CLAUDE.md`](.claude/CLAUDE.md) — AI/人間共通の作業ガイド + ADR

## Workflow

### 1. Issue から始める

例外なく Issue を切る。「ちょっとした修正」も含む。

### 2. ブランチを切る

```
feat/<issue-number>-<short-name>
fix/<issue-number>-<short-name>
docs/<issue-number>-<short-name>
chore/<issue-number>-<short-name>
```

### 3. TDD で実装

1. **`tdd-spec`** — 振る舞いをテストに書く
2. レビュー — 「このテストが通れば仕様を満たす」と言えるか
3. **`tdd-impl`** — テストを通す最小実装
4. リファクタ — テストを変えずに構造改善

テストを安易に変えない。**仕様 = テスト**。

### 4. PR を出す

PR テンプレートは [`.github/PULL_REQUEST_TEMPLATE.md`](.github/PULL_REQUEST_TEMPLATE.md)。

## Code Quality Rules

詳細は [`.claude/rules/`](.claude/rules/) 配下。要点：

- **強制 unwrap 禁止**（Swift `!` / `try!` / `as!`、Rust `unwrap()` / `expect()`、TS non-null assertion `!`（例: `foo!.bar`）等。テストも本番も）
- **REALWORLD（時間・乱数・FS・env・network・subprocess）は port 化**
- **Domain 層は純粋データ・coverage 除外**
- **DI / Orchestrator は wiring のみ・coverage 除外**
- **カバレッジ 95% 以上**（除外モジュール除く）

## Commit message

[Conventional Commits](https://www.conventionalcommits.org/) に準拠：

```
<type>(<scope>): <short>

<body>
```

| 項目 | 値 |
|---|---|
| `type` | `feat` / `fix` / `refactor` / `docs` / `test` / `chore` |
| `scope` | プロジェクト構造に応じて適宜 |

## Language

- やり取り（Issue / PR / コミットメッセージ）：日本語
- コード（識別子・コメント）：英語
