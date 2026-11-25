---
name: ux-playtest-agent
description: |-
  Autonomously playtest Footballsim on desktop by interacting with the live
  game: one league-loop session with at least one match simulated to full
  time; find UX bugs, inconsistencies, and enhancements; upload screenshots
  (and short clips when needed) to a wiki Evidence page; file GitHub issues
  with links — no code fixes. Ask the user only on true blockers. Use when
  the user asks for a UX playtest, UI bug hunt via the real game, or when
  the daily orc schedule runs this agent.

  Examples:
    - daily 1am dispatch → launch game, playtest, wiki evidence, file issues, stop
    - "UX playtest the menus and a match" → same interactive path
    - "playtest and file what you find" → full autonomy; no draft confirm
---

# UX playtest agent

One **desktop UX playtest** per run. Deliverable: a wiki Evidence run page plus
zero or more GitHub issues (`todo` + `bug` or `enhancement`). Do **not** fix
code, open PRs, or edit Simulation rules.

## Scope (locked)

| Item | Rule |
|------|------|
| Platform | Desktop only |
| How | Interact with the **live** game (keyboard/mouse into the Godot window) |
| Session | One **league-loop** playtest: main menu → league/fixture surfaces → **≥1 match** simulated in-client **to full time** |
| Filing | Full autonomy — no draft or duplicate confirm with a human |
| Evidence | Wiki page; issues **link** it |
| Legibility | Judge non-match chrome at more than one window size (see below); the match HUD's own sizing is not a finding |
| Out of scope | Code fixes, PRs, wiki rule edits, pure sim “wrong score” unless it shows as UX |

Highlights mode + speed keys are fine so wall-clock stays reasonable. Do not
require simulating every Premier League fixture unless the product exposes a
batch league-sim UX; cover league chrome (table/encyclopedia/fixtures) plus
≥1 complete match.

## Sources

| Source | Role |
|--------|------|
| [`launch-game`](../launch-game/SKILL.md) | Keep Godot alive after the agent shell exits |
| [`references/playbook.md`](references/playbook.md) | Launch, xdotool, screenshots, optional ffmpeg |
| [`references/evidence.md`](references/evidence.md) | Wiki Evidence hierarchy for UX runs |
| [`references/issue-body.md`](references/issue-body.md) | Issue title/body shapes |
| [`../file-github-issue/SKILL.md`](../file-github-issue/SKILL.md) | Labels + `gh issue create` pattern (skip interview) |
| [`../_shared/plain-english.md`](../_shared/plain-english.md) | Human-facing wording |
| Product README / in-game HUD | Controls and chrome |

**Not this agent:** implementing a filed `todo` → [`resolve-issue-agent`](../resolve-issue-agent/SKILL.md);
wiki ambiguity → [`elucidate-design-agent`](../elucidate-design-agent/SKILL.md);
human bug report interview → [`file-github-issue`](../file-github-issue/SKILL.md).

## Workflow

```text
- [ ] 1. Orient + launch
- [ ] 2. Interactive playtest (league loop + ≥1 match to FT)
- [ ] 3. Capture evidence for each finding
- [ ] 4. Wiki Evidence run page
- [ ] 5. De-dupe + file issues (autonomous)
- [ ] 6. Stop and report
```

### 1. Orient + launch

Sync context on current `main` (commit SHA). Follow [`launch-game`](../launch-game/SKILL.md)
so the window stays up. Prefer a clean session (`--restart` if a stale instance
blocks input).

### 2. Interactive playtest

Drive the **actual** window per [`references/playbook.md`](references/playbook.md).
Minimum path:

1. Main menu — Start Sim / Settings / Quit affordances
2. League-facing UX — fixture picker, league encyclopedia/table, club/player pages as reachable
3. At least one match — watch controls (pause, speed, highlights/full, skip, camera, pin/hover, names); continue until **full time** and FT summary
4. Note UX bugs, visual inconsistencies, confusing copy/layout, dead controls, contrast/overlap, and enhancement ideas

**Judge by looking at the screen** (Read captured PNGs). Do not treat headless
`tools/sim_round.gd` as the playtest.

### 2b. Legibility pass (non-match chrome)

Read the type, not just the layout. Capture every non-match surface — main menu,
settings, quit confirm, league hub, table, fixtures/calendar, match report,
full-time summary, encyclopedia and fixture picker — **twice**: at the default
window and at a large fullscreen-sized window (see
[`references/playbook.md`](references/playbook.md)). Then judge:

- Captions, hints and secondary copy read comfortably at a normal desktop
  distance; nothing is a hairline.
- Growing the window enlarges the type and chrome; it must not leave fixed-size
  text on a large sheet.
- Text stays inside its panels and rows at both sizes (no clipping, no overlap).
- Scope is the **tightened `RUB-P1-07`** and the wiki Design Record for non-match
  type legibility. The match overlay's own sizing is **not** in scope: never file
  a finding that asks the broadcast HUD to grow.

A failing finding names the surface, the window size, and what looked small —
screenshot proof from both sizes belongs on the run page.

### 3. Capture evidence

For each finding worth filing: screenshot (or ≤20s clip if motion-only). Stage
files for the wiki clone. Prefer stills.

### 4. Wiki Evidence run page

Clone `waigore/footballsim.wiki`, write `evidence/ux-playtest-YYYYMMDD.md` +
images, update Evidence home, push. Details:
[`references/evidence.md`](references/evidence.md).

### 5. De-dupe + file issues

Search open issues for the same symptom. If a clear duplicate exists: comment
on it with the Evidence link (and finding id); do not open a second issue.
Otherwise create one issue per distinct finding using
[`references/issue-body.md`](references/issue-body.md) — include the Evidence
URL. Labels: `todo` + `bug` (bugs/inconsistencies) or `todo` + `enhancement`.

No human confirm. Plain English titles/bodies.

### 6. Stop and report

List: Evidence page URL, issue URLs (or “none — no new UX issues”), match(es)
played, commit SHA. Quit or leave the game; do not babysit fixes.

## Done when

- Live desktop playtest covered every non-match surface at two window sizes and league chrome + ≥1 match to FT
- Non-match type judged comfortable and viewport-scaled (`RUB-P1-07`); match HUD size not filed as a defect
- Wiki run page published (even if zero findings — note a clean pass)
- New issues filed or duplicates commented with evidence links — each citing the surface, window size and Design Record when it is a legibility finding
- No game code or Simulation-rules wiki edits
