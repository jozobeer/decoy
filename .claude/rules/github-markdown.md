# GitHub Markdown Conventions

Conventions for composing GitHub markdown — issue bodies, PR
descriptions, review comments, replies, release notes — beyond plain
markdown. GitHub renders a sanitized subset of HTML; these conventions
stay within that subset and target readability under GitHub's CSS.

Sections:

- **Shields.io Badges** — visual metadata at the top of bodies/replies
- **Mojiemoji Stamps** — when to use expressive Japanese text stamps
  (rendering details live in the `mojiemoji-github` skill)
- **HTML Notation** — sanitizer-safe HTML inside markdown
- **Collapsible Sections** — `<details>` to fold verbose content

---

## Shields.io Badges (Experimental)

**CRITICAL: All badges in a group MUST be on a single line — no line
breaks between `![]()`s.** GitHub Markdown only renders them horizontally
when they share the same line. This is the most common mistake.

Add shields.io badges at the top of issue bodies, PR descriptions, and
review comment responses to convey key metadata at a glance. Use static
badges via `https://img.shields.io/badge/<label>-<value>-<color>`.
Encode spaces as `%20` and hyphens as `--` in values.

**Private repository limitation**: shields.io cannot access the GitHub
API without authentication, so dynamic badges do not work for private
repos. Do not use badges whose values change over time (`diff`, `files`,
etc.) in private repos — they become stale and cannot auto-update.
Badges with fixed values (`type`, `breaking`, `complexity`, etc.) are
fine in private repos.

### Color Conventions

| Color | Meaning | Use for |
|-------|---------|---------|
| `blue` | Neutral / info | type, scope, platform |
| `green` | Positive / small / easy | low complexity, small estimate |
| `yellow` | Caution / moderate | medium complexity, some impact |
| `orange` | Warning / significant | high complexity, broad impact |
| `red` | Critical / breaking | critical severity, breaking change |
| `purple` | AI / tooling related | AI friendliness |
| `grey` | Supplementary | depends on, relates to |

### Issue Badges

Select badges based on issue type. Place them at the top of the body,
one blank line before the description.

#### Feature / Enhancement

| Badge | Values | Color rule |
|-------|--------|------------|
| `type` | `feat` / `enhance` / `refactor` / `docs` / `chore` | `blue` |
| `priority` | `critical` / `high` / `medium` / `low` | red → orange → yellow → green |
| `complexity` | `trivial` / `moderate` / `complex` / `architect` | green → yellow → orange → red |
| `estimate` | `~50 lines` / `~200 lines` / `~500 lines` | green(<100) → yellow(<300) → orange(<500) → red(500+) |
| `max lines` | `100` / `200` / `400` | matches estimate color scale |
| `AI` | `auto` / `assisted` / `pair` / `manual` | green → blue → yellow → orange |
| `platform` | `iOS` / `Android` / `Web` / `CLI` / `cross` | `blue` |
| `depends on` | `#123` | `grey` |

- `AI: auto` — Copilot / Claude single-shot can handle it
- `AI: assisted` — AI writes most of it, human reviews and adjusts
- `AI: pair` — interactive collaboration with AI
- `AI: manual` — human-driven, AI assists marginally

#### Bug

| Badge | Values | Color rule |
|-------|--------|------------|
| `type` | `bug` | `red` |
| `severity` | `critical` / `major` / `minor` / `cosmetic` | red → orange → yellow → green |
| `impact` | `all%20users` / `subset` / `edge%20case` | red → orange → yellow |
| `reproducibility` | `always` / `sometimes` / `rare` | red → orange → yellow |
| `priority` | (same as feature) | (same) |
| `AI` | (same as feature) | (same) |
| `workaround` | `exists` / `none` | green / orange |
| `data loss` | `yes` / `no` / `possible` | red / green / yellow |
| `depends on` | `#123` | `grey` |

### PR Badges

Place at the top of the PR body, one blank line before the summary.

| Badge | Values | Color rule |
|-------|--------|------------|
| `type` | `feat` / `fix` / `refactor` / `docs` / `chore` / `test` | `blue` |
| `breaking` | `yes` / `no` | red / green |
| `scope` | free text (e.g. `auth`, `api`, `ui`) | `blue` |
| `diff` | `+142%20--30` | `green` for net add, `red` for net delete, `yellow` for balanced |
| `files` | count (e.g. `3%20files`) | green(<5) → yellow(<15) → orange(<30) → red(30+) |
| `tests` | `passing` / `added` / `none` / `failing` | green / green / yellow / red |
| `migration` | `required` / `none` | orange / green |
| `status` | `draft` / `ready` / `blocked` | yellow / green / red |
| `review` | `quick%20look` / `thorough` / `domain%20expert` | green → yellow → orange |
| `estimate vs actual` | `~200%20→%20+180` | green(within 20%) → yellow(within 50%) → red(50%+) |
| `depends on` | `#123` | `grey` |

- `review` — signals review effort: `quick look` for trivial changes,
  `domain expert` when specialized knowledge is required
- `estimate vs actual` — compares estimated lines from the issue with
  actual diff stats, useful for calibrating future estimates

### Review Comment Response Badges

When replying to PR review comments, prepend an action badge to signal
the response type at a glance. Place the badge on the first line of the
reply, followed by the explanation.

| Badge | Meaning | Color |
|-------|---------|-------|
| `action: fixed` | Addressed as suggested | `green` |
| `action: by design` | Intentional — proven by test or docs | `blue` |
| `action: test added` | Missing coverage, test added | `purple` |
| `action: deferred` | Out of scope, tracked in a new issue | `yellow` |
| `action: wontfix` | Intentionally kept as-is (must include reason) | `grey` |

### Format Examples

**REMINDER: All badges MUST be on a single line (no line breaks).**

```markdown
<!-- Feature Issue -->
![type](https://img.shields.io/badge/type-feat-blue) ![priority](https://img.shields.io/badge/priority-high-orange) ![complexity](https://img.shields.io/badge/complexity-moderate-yellow) ![estimate](https://img.shields.io/badge/estimate-~200%20lines-yellow) ![AI](https://img.shields.io/badge/AI-assisted-blue)

<!-- Bug Issue -->
![type](https://img.shields.io/badge/type-bug-red) ![severity](https://img.shields.io/badge/severity-major-orange) ![impact](https://img.shields.io/badge/impact-all%20users-red) ![reproducibility](https://img.shields.io/badge/reproducibility-always-red) ![workaround](https://img.shields.io/badge/workaround-none-orange)

<!-- Pull Request -->
![type](https://img.shields.io/badge/type-feat-blue) ![breaking](https://img.shields.io/badge/breaking-no-green) ![scope](https://img.shields.io/badge/scope-auth-blue) ![diff](https://img.shields.io/badge/diff-+142%20--30-green) ![tests](https://img.shields.io/badge/tests-added-green) ![review](https://img.shields.io/badge/review-thorough-yellow)

<!-- Review comment reply — always leave a blank line between badge and body -->
![action](https://img.shields.io/badge/action-fixed-green)

Fixed in [abc1234](https://github.com/OWNER/REPO/commit/abc1234567890abcdef1234567890abcdef123456).

![action](https://img.shields.io/badge/action-by%20design-blue)

This is intentional. Verified by `test_xxx`.

![action](https://img.shields.io/badge/action-test%20added-purple)

Coverage was missing — added in [abc1234](https://github.com/OWNER/REPO/commit/abc1234567890abcdef1234567890abcdef123456).

![action](https://img.shields.io/badge/action-deferred-yellow)

Out of scope for this PR. Tracked in #789.

![action](https://img.shields.io/badge/action-wontfix-grey)

Keeping as-is for performance reasons. Details: ...
```

### Guidelines

- Badge selection is contextual — include only what is relevant, skip
  badges that add no information (e.g. `migration: none` on a docs PR)
- When data is available programmatically (diff stats, file count),
  compute values automatically rather than guessing
- Color is semantic, not decorative — follow the color conventions above
  so readers build intuition over time
- Keep badge order consistent: type → severity/priority → size/scope →
  AI/review → dependencies
- **Always link commit hashes as markdown links, never bare text.** Use
  `[<short>](https://github.com/<owner>/<repo>/commit/<full-sha>)` —
  short hash (7–10 chars) as display, full 40-char SHA as target. Bare
  hashes are invisible in email/notification views and not reliably
  auto-linked across contexts. Resolve the full SHA with
  `gh api repos/<owner>/<repo>/commits/<short> --jq .sha` if only the
  short form is known. This applies to all GitHub-visible text: PR
  bodies, issue bodies, review replies, cross-links.

---

## Mojiemoji Stamps

For Japanese GitHub bodies, prefer expressive `mojiemoji.jozo.beer`
image stamps over plain text on emotional pivots, status/mood/approval,
caution, and punch-line emphasis. Rendering details (URL params,
animations, presets, inline vs block HTML) live in the
`mojiemoji-github` skill — invoke it rather than hand-crafting URLs.

### When to use

- **Block stamps** (own-line markdown `![alt](url)`): headings, callouts,
  closing lines, checklist toppers — `レビュー歓迎`, `マージ完了`,
  `LGTM`, `あとちょい`
- **Inline stamps** (HTML `<img height="24" align="absmiddle">`):
  mid-sentence punch-line emphasis — `これは【マジで】やばい【バグ】ですね`
- **Pair with badges**: badges = metadata, stamps = mood. They live in
  different paragraphs; do not interleave on the same line

### When NOT to use (do-not-stamp)

- API names, function names, file paths, version strings — clarity over
  flair
- Apology bodies, security/legal/compliance text, requirements and
  acceptance criteria — readers must skim these without distraction
- English-only bodies — stamps are tuned for Japanese phrases
- More than 2 inline stamps in a single sentence — visual noise

### Always offer/ask

Before decorating, ask the user (or signal the intent in a one-liner)
unless they have already requested stamps. Never auto-decorate. The
`mojiemoji-github` skill description encodes the proactive offer.

---

## HTML Notation

GitHub's markdown sanitizer accepts a useful subset of HTML. Use it when
plain markdown can't express the intent.

### Allowed and useful tags

| Tag | Use for | Notes |
|-----|---------|-------|
| `<img>` | inline stamps, sized images | `style` is stripped — use integer pixel `height`/`width`. `align="absmiddle"` for mid-sentence vertical centering |
| `<details>` / `<summary>` | collapsible sections | See § Collapsible Sections |
| `<sub>` / `<sup>` | unit suffixes, footnote markers | `H<sub>2</sub>O`, `x<sup>2</sup>` |
| `<kbd>` | keyboard keys | `<kbd>⌘</kbd> + <kbd>K</kbd>` — renders as a key-cap |
| `<br>` | hard line break inside table cells | Plain markdown line breaks don't work inside `\|...\|` |
| `<picture>` / `<source>` | dark/light theme art | Pair with `media="(prefers-color-scheme: dark)"` |

### Sanitizer constraints

- **`style` attribute is stripped** — never rely on inline CSS. Use HTML
  attributes (`height`, `width`, `align`) instead
- **CSS units are ignored** — pixel integers only (`height="24"`, not
  `height="24px"` or `height="1.5em"`)
- **`<script>`, `<iframe>`, event handlers** are stripped entirely
- **`class` and `id` are stripped** in most contexts
- **`align="absmiddle"`** is a legacy attribute but still respected by
  GitHub's renderer for inline image vertical alignment

### Sizing inline images

For mojiemoji and similar inline image stamps:

```html
<img src="..." alt="マジで" height="24" align="absmiddle">
```

`height="24"` reads cleanly at body font size. Going below 20 makes
short Japanese stamps hard to read.

---

## Collapsible Sections (`<details>`)

Wrap verbose sections in `<details><summary>label</summary>...</details>`
so the default view stays scannable. The user prefers concise GitHub
surfaces; collapsing optional context keeps the top-of-page tight while
preserving the full information.

### When to fold

- Full stack traces, raw command output, large logs
- Long before/after diffs, full benchmark tables
- Secondary rationale, FAQ-style addenda, lengthy migration notes
- Reproduction steps that exceed ~10 lines
- Quoted upstream issue/PR bodies

### When to keep visible

- Headline, decision, and next action
- Badges (always at the top, never inside `<details>`)
- The 1–3 sentences a reader needs to act

### How

```markdown
<details>
<summary>詳細な再現手順</summary>

1. ...
2. ...

</details>
```

- Pair `<summary>` with a meaningful label — never just "Details"
- Leave a blank line after `<summary>` and before `</details>` so the
  inner content parses as markdown
- Add `open` (`<details open>`) only when you want the section visible
  by default but still collapsible

### Combine with badges

Badges go above the fold. The collapsible body sits below.

```markdown
![type](https://img.shields.io/badge/type-bug-red) ![severity](https://img.shields.io/badge/severity-major-orange)

Crash on cold start when the cache directory is missing.

<details>
<summary>Stack trace and reproduction logs</summary>

```
... (long output)
```

</details>
```
