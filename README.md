# Decoy

> 撮ることと、見せることを、別の蛇口にする

Record a short clip and swap your virtual camera between live and decoy — a macOS menu bar app.

---

## Dream

Web 会議や配信中、ほんの少し席を立ちたい瞬間がある。でも「離席します」と宣言するほどでも、カメラを切るほどでもない。その間だけ、事前に録った自分の映像をループさせて「いる」ことにする。

鍵は **撮ることと見せることの分離**。録画は常にカメラそのものを録り、放送中のデコイは録らない。だから「デコイを流したまま、次のデコイを録る」「ライブを流しながら、念のため録っておく」が自然にできる。録ったクリップはいつでも放送にすり替えられる。

再生は **Once / Loop / PingPong** の 3 モード。Once は再生完了で自動的に Live に戻る「投げっぱなし」モード、Loop / PingPong は止めるまで回り続ける（PingPong は往復でシームを目立たせない）。

操作はメニューバーとショートカットキーだけ。動画編集ツールでも複数クリップ管理ツールでもなく、**「今だけ、いることにしておく」を最短操作で叶える道具**。

詳細・選定の経緯は [`.claude/CLAUDE.md`](./.claude/CLAUDE.md) の ADR セクション参照。

---

## アーキテクチャ

- お手本骨格：[GeneralD/lyra](https://github.com/GeneralD/lyra)
- 詳細は [`.claude/CLAUDE.md`](./.claude/CLAUDE.md)

---

## 開発

TDD で進める。詳細は [`.claude/CLAUDE.md`](./.claude/CLAUDE.md)。

```sh
# 例（言語に応じて差し替え）
xcodebuild -resolvePackageDependencies -project Decoy.xcodeproj
xcodebuild test -scheme Decoy -destination 'platform=macOS'
xed .
```

---

## License

MIT（[LICENSE](./LICENSE)）
