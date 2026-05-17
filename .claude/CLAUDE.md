# CLAUDE.md — Decoy

このリポは [Repo-Forge](https://github.com/jozobeer/repo-forge) から scaffold された **decoy**。
Repo-Forge とは独立しており、Repo-Forge が消えても動く（**Standalone**）。

---

## Dream（このプロダクトの存在理由）

> 撮ることと、見せることを、別の蛇口にする

詳細は [`README.md`](../README.md) と起点 Issue / PR を参照。
**Dream を薄める変更を検出したら立ち止まる**（Domain 改変要求の段で「Dream の進化か変質か」を問う）。

---

## アーキテクチャ ADR ― scaffold 時の選定

### 採用したお手本

- **モノリポ骨格**：[GeneralD/lyra](https://github.com/GeneralD/lyra)
- **部分パターン**：なし（lyra 単独で十分）

### 採用したパターン

- `swift-dependencies` 経由の DI（`@Dependency` / `liveValue` / `testValue`）
- `Clock` 抽象（時間は port 化）
- Domain は純粋データ（Entity 規約：computed property のロジック禁止）
- coverage-ignored: `Domain` / `DependencyInjection`
- `Recorder` と `Broadcaster` は独立 actor（共有は CameraInput 参照のみ）
- `AppCommand` enum で UI 入力経路を統一（adapter は AppCommand を発行するだけ）
- AVCaptureSession / CMIO Camera Extension は port 化（`CameraSource`, `VirtualCameraSink` protocol）
- メニューバー UI は SwiftUI `MenuBarExtra` ＋ 最小構成
- Domain サブディレクトリは port の責務で層別（lyra 流）：
  - `DataSource/` ― OS への薄い入力 port（`CameraSource` / `CameraPermission` / `HotkeyService`）
  - `Sink/` ― OS への出力 port（`VirtualCameraSink`）
  - `Transport/` ― IPC port（`FrameTransport`）
  - `Repository/` ― 永続化 port（`ClipStore`）
  - `Installer/` ― System Extension 操作 port（`CameraExtensionInstaller`）
  - Phase 3 で `UseCase/` が増える前提の予約

### 捨てたパターン

- 動画編集 UI（トリミング・フィルタ・トランジション）
- 複数クリップ管理（プレイリスト的なもの）
- 音声処理・ミックス
- TCA などの重量級アーキテクチャ（lyra の素朴な swift-dependencies + Clean Architecture で十分）
- メインウィンドウ／ドックアイコン（メニューバー常駐のみ）
- 録画 source として Output bus を使う（Capture は常にカメラから ＝ Domain 不変条件）

### 依存方向

常に **外 → 内**（Clean Architecture / hexagonal）：

```
adapter ──> usecase ──> domain
   ▲           ▲          ▲
   └─ port ────┘          │
                          │
   Domain は外部の何にも依存しない（純粋）
```

---

## 作業の原則

### コード品質

- **TDD**：[`tdd-spec`](./skills/tdd-spec/SKILL.md) で先にテストを書き、[`tdd-impl`](./skills/tdd-impl/SKILL.md) で実装を埋める
- **テスト = 仕様**。テストを安易に変えない
- **REALWORLD（時間・乱数・FS・env・network・外部API・subprocess）は port 化**
- **強制 unwrap 禁止**（Swift `!` / `try!` / `as!`、Rust `unwrap()` / `expect()`、TS non-null assertion `!`（例: `foo!.bar`））。エラーは握り潰さず明示的に伝播
- **カバレッジ 95% 以上**（Domain / DI / Orchestrator は除外）
- 装飾的な綺麗さは諦めてよい。**ドメインの整然な表現は諦めない**

### Standalone 原則

- このリポは Repo-Forge に依存しない（`uses: jozobeer/repo-forge/...` などは禁止）
- secrets は repo-level に焼き付ける（org-level 依存禁止）
- 雛形は scaffold 時にコピー済み。Repo-Forge 側の更新を追従する義務はない

---

## 言語

- ユーザーとの応答：日本語（default: 日本語）
- ドキュメント：日本語
- コード：英語（識別子・コメント）

### ユビキタス言語

- `Clip` — 録画素材
- `Recorder` — Capture actor（常にカメラから録る）
- `Broadcaster` — Output actor（live / playback を切替）
- `OutputMode` — `Live` / `Playback`
- `RecordingState` — `Idle` / `Recording`
- `PlaybackMode` — `Once` / `Loop` / `PingPong`
- `AppCommand` — `startRecording` / `stopRecording` / `startDecoy` / `returnToLive` / `setPlaybackMode(PlaybackMode)`（ショートカットキー・メニューバー両方ともこの enum に集約される統一コマンド面）

---

## ローカル規約（`.claude/`）

ルール（`.claude/rules/`）― リポ内コピー保管、`~/.config/claude/` がなくても自走する：

- [`code-philosophy.md`](./rules/code-philosophy.md)
- [`development-practices.md`](./rules/development-practices.md)
- [`coverage-ignored-modules.md`](./rules/coverage-ignored-modules.md)
- [`git-workflow.md`](./rules/git-workflow.md)
- [`github-markdown.md`](./rules/github-markdown.md)
- [`conventions/swift.md`](./rules/conventions/swift.md) ― 言語固有の規約（swift）

スキル（`.claude/skills/`）― 同名スキルがあればプロジェクト版が優先：

- [`tdd-spec`](./skills/tdd-spec/SKILL.md)
- [`tdd-impl`](./skills/tdd-impl/SKILL.md)

---

## Anti-Pattern

- Dream に無い概念を Domain に追加する
- domain / usecase で REALWORLD を直接呼ぶ
- adapter で強制 unwrap（`!` / `unwrap()` 等）を使う
- テストを書かずに実装する
- 装飾的なリファクタを「綺麗にしました」と PR で出す
