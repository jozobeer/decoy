<p align="center">
  <img src="docs/images/hero-v1.png" alt="Decoy — 撮ることと見せることを、別の蛇口にする" width="900">
</p>

# Decoy

![status](https://img.shields.io/badge/status-bootstrapping-yellow) ![platform](https://img.shields.io/badge/platform-macOS-blue) ![language](https://img.shields.io/badge/language-Swift-orange) ![license](https://img.shields.io/badge/license-MIT-green) ![methodology](https://img.shields.io/badge/methodology-TDD-green) [![codecov](https://codecov.io/gh/jozobeer/decoy/branch/main/graph/badge.svg)](https://codecov.io/gh/jozobeer/decoy)

> 撮ることと、<img src="https://mojiemoji.jozo.beer/emoji/%E8%A6%8B%E3%81%9B%E3%82%8B?font=pixel&color=06b6d4&animation=roulette&speed=normal&background=transparent&outline=darker&outline_width=2" alt="見せる" height="20" align="absmiddle"> ことを、別の <img src="https://mojiemoji.jozo.beer/emoji/%E8%9B%87%E5%8F%A3?font=mincho&color=f87171&animation=gatagata&speed=slow&background=transparent&outline=darker&outline_width=2" alt="蛇口" height="20" align="absmiddle"> にする

Record a short clip and swap your virtual camera between live and decoy — a macOS menu bar app.

---

## Dream

Web 会議や配信中、ほんの少し <img src="https://mojiemoji.jozo.beer/emoji/%E5%B8%AD?font=maru&color=ec4899&animation=mochimochi&speed=slow&background=transparent&outline=darker&outline_width=2" alt="席" height="20" align="absmiddle"> を立ちたい瞬間がある。でも「<img src="https://mojiemoji.jozo.beer/emoji/%E9%9B%A2%E5%B8%AD?font=mincho&color=f97316&animation=wave&speed=slow&background=transparent&outline=darker&outline_width=2" alt="離席" height="20" align="absmiddle"> します」と宣言するほどでも、カメラを切るほどでもない。その間だけ、事前に <img src="https://mojiemoji.jozo.beer/emoji/%E9%8C%B2%E3%82%8B?font=gothic-bold&color=f59e0b&animation=norinori&speed=slow&background=transparent&outline=darker&outline_width=2" alt="録る" height="20" align="absmiddle"> っておいた自分の映像をループさせて「<img src="https://mojiemoji.jozo.beer/emoji/%E3%81%84%E3%82%8B?font=maru-bold&color=a855f7&animation=poyoon&speed=normal&background=transparent&outline=darker&outline_width=2" alt="いる" height="20" align="absmiddle">」ことにする。

鍵は **撮ることと <img src="https://mojiemoji.jozo.beer/emoji/%E8%A6%8B%E3%81%9B%E3%82%8B?font=pixel&color=06b6d4&animation=roulette&speed=normal&background=transparent&outline=darker&outline_width=2" alt="見せる" height="20" align="absmiddle"> ことの <img src="https://mojiemoji.jozo.beer/emoji/%E5%88%86%E9%9B%A2?font=maru-bold&color=3b82f6&animation=spring&speed=normal&background=transparent&outline=darker&outline_width=2" alt="分離" height="20" align="absmiddle">**。録画経路は常にカメラそのものを録り、放送中のデコイは録らない。だから「デコイを流したまま、次のデコイを録る」「ライブを流しながら、念のため録っておく」が自然にできる。録ったクリップはいつでも放送にすり替えられる。

再生は **Once / Loop / PingPong** の 3 モード。Once は再生完了で自動的に Live に戻る「投げっぱなし」モード、Loop / PingPong は止めるまで回り続ける（PingPong は往復でシームを目立たせない）。

操作はメニューバーとショートカットキーだけ。動画編集ツールでも複数クリップ管理ツールでもなく、**「今だけ、<img src="https://mojiemoji.jozo.beer/emoji/%E3%81%84%E3%82%8B?font=maru-bold&color=a855f7&animation=poyoon&speed=normal&background=transparent&outline=darker&outline_width=2" alt="いる" height="20" align="absmiddle"> ことにしておく」を <img src="https://mojiemoji.jozo.beer/emoji/%E6%9C%80%E7%9F%AD?font=dela&color=ef4444&animation=buruburu&speed=fast&background=transparent&outline=darker&outline_width=2" alt="最短" height="20" align="absmiddle"> 操作で叶える道具**。

詳細・選定の経緯は [`.claude/CLAUDE.md`](./.claude/CLAUDE.md) の ADR セクション参照。

---

## アーキテクチャ

カメラの <img src="https://mojiemoji.jozo.beer/emoji/%E6%B5%81%E3%82%8C?font=gothic-bold&color=06b6d4&animation=scroll&speed=slow&background=transparent&outline=darker&outline_width=2" alt="流れ" height="20" align="absmiddle"> は `Recorder` と `Broadcaster` の 2 つの独立 actor に <img src="https://mojiemoji.jozo.beer/emoji/%E5%88%86%E9%9B%A2?font=maru-bold&color=3b82f6&animation=spring&speed=normal&background=transparent&outline=darker&outline_width=2" alt="分離" height="20" align="absmiddle"> されている。`Recorder` は常に `CameraSource` から <img src="https://mojiemoji.jozo.beer/emoji/%E9%8C%B2%E3%82%8B?font=gothic-bold&color=f59e0b&animation=norinori&speed=slow&background=transparent&outline=darker&outline_width=2" alt="録る" height="20" align="absmiddle"> り、`Broadcaster` は live モードで `CameraSource` を、playback モードで `Clips` を <img src="https://mojiemoji.jozo.beer/emoji/%E8%A6%8B%E3%81%9B%E3%82%8B?font=pixel&color=06b6d4&animation=roulette&speed=normal&background=transparent&outline=darker&outline_width=2" alt="見せる" height="20" align="absmiddle">。両者の出力は `VirtualCameraSink`（CMIO Camera Extension）経由で Zoom / OBS / etc. に届く。

```mermaid
flowchart LR
    Camera[CameraSource]
    Camera -->|always capture| Recorder[Recorder<br/>actor]
    Recorder --> Clips[(Clips<br/>store)]
    Camera -.->|Live mode| Broadcaster[Broadcaster<br/>actor]
    Clips -.->|Playback mode<br/>Once / Loop / PingPong| Broadcaster
    Broadcaster --> VC[VirtualCameraSink<br/>CMIO Camera Extension]
    VC --> Apps[Zoom / OBS / etc.]

    classDef capture fill:#dbeafe,stroke:#3b82f6,color:#1e3a8a
    classDef broadcast fill:#fef3c7,stroke:#f59e0b,color:#7c2d12
    classDef sink fill:#dcfce7,stroke:#22c55e,color:#14532d
    class Camera,Recorder,Clips capture
    class Broadcaster,VC broadcast
    class Apps sink
```

実線（`-->`）は常時通る経路、点線（`-.->`）は `OutputMode`（`Live` / `Playback`）でどちらか片方だけ通る経路。`Recorder` は出力経路の状態によらず常に `CameraSource` を見ている、という Dream の不変条件がそのまま図に出る。

- お手本骨格：[GeneralD/lyra](https://github.com/GeneralD/lyra)
- 詳細は [`.claude/CLAUDE.md`](./.claude/CLAUDE.md)

---

## 開発

TDD で進める。詳細は [`.claude/CLAUDE.md`](./.claude/CLAUDE.md)。

### SPM (lib targets / tests)

```sh
swift build
swift test
```

### Xcode (Decoy.app / SystemExtension bundle)

`Decoy.xcodeproj` は [xcodegen](https://github.com/yonaskolb/XcodeGen) で `project.yml` から生成する。`.xcodeproj` 自体は gitignore されていて、source of truth は `project.yml`。

```sh
brew install xcodegen   # 初回のみ
xcodegen generate       # project.yml → Decoy.xcodeproj
xed .
```

CI でも同じ手順で再生 → `xcodebuild build`。署名は release tag workflow で別途。

---

## License

MIT（[LICENSE](./LICENSE)）
