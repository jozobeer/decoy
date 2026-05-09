<!--
Decoy の PR テンプレート。
.claude/CLAUDE.md の Anti-Pattern を疑ったら必ず明記。
-->

## 概要

<!-- 何をしたか、1〜3行 -->

## 関連 Issue

<!-- Closes #123 / Refs #456 -->

## Dream への影響

<!--
このプロダクトの存在理由（Dream）に対してどう作用するか：
- 進化：Dream を強化する
- 保護：Dream を守る補強（テスト・抽象化・リファクタ）
- 変質：Dream そのものを変える ← レビュー必須
- 無関係：技術的副作用のみ
-->

- [ ] 進化
- [ ] 保護
- [ ] 変質（レビュー必須）
- [ ] 無関係

**根拠**：

## TDD ステータス

- [ ] `tdd-spec`：先にテストを書いた
- [ ] `tdd-impl`：そのテストを満たす最小実装を書いた
- [ ] テストを変更した（変更理由を以下に明記）
- [ ] N/A（ドキュメント単独）

**テスト変更があれば理由**：

## REALWORLD 抽象化

<!-- 時間・乱数・FS・env・network・外部API・subprocess を直接呼んでいないか -->

- [ ] domain / usecase で REALWORLD を直接呼んでいない
- [ ] 新規 REALWORLD は port 化した
- [ ] N/A

## カバレッジ

- [ ] 95% 以上を維持（Domain / DI / Orchestrator は除外）
- [ ] coverage-ignored モジュールに実装を入れていない
- [ ] N/A

## Anti-Pattern チェック

- [ ] Dream に無い概念を Domain に追加していない
- [ ] adapter で `unwrap()` / `expect()` を使っていない
- [ ] 装飾的なリファクタ単独 PR ではない

## 補足
