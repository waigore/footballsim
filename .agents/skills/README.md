# Project skills

Canonical skill bodies live here (one folder per skill). Native facades and authoring rules: [`docs/skills.md`](../../docs/skills.md).

## Catalog

| Skill | Purpose |
|-------|---------|
| [`audit-deferred-agent`](audit-deferred-agent/SKILL.md) | Audit deferred vs code/wiki; re-rank gaps; update `docs/deferred.md`; docs-only PR |
| [`babysit-pr-agent`](babysit-pr-agent/SKILL.md) | Unblock one same-repo PR for squash auto-merge |
| [`calibrate-poisson-model`](calibrate-poisson-model/SKILL.md) | Audit λ + Monte Carlo vs the last-10 PL scoring envelope; dual gate (bands + 1X2); land constants + tests |
| [`capture-requirements`](capture-requirements/SKILL.md) | Interactive multi-dimension feature capture; confirm; container + sub-issues via file-github-issue |
| [`clarify-github-issue`](clarify-github-issue/SKILL.md) | Chat: accept/revise/reject one open `question` issue → `todo`+`bug`/`enhancement` or close |
| [`elucidate-design-agent`](elucidate-design-agent/SKILL.md) | Find unclear wiki rules (P5-first); file `question` issue with precise design; stop |
| [`export-android-debug`](export-android-debug/SKILL.md) | Publish debug APK via Actions + `android-debug/` release; report download URL |
| [`file-github-issue`](file-github-issue/SKILL.md) | Interview bug/feature reports; duplicate check; analyze; file GitHub issue (`todo` + `bug`/`enhancement`) |
| [`fix-tests-agent`](fix-tests-agent/SKILL.md) | Hourly (gated on open `ci-tier2`); fix full-suite failure; PR; babysit; close issue |
| [`launch-game`](launch-game/SKILL.md) | Desktop launch via `tools/launch_game.sh` (LaunchServices detach; optional clear-cache/restart) |
| [`implement-feature-agent`](implement-feature-agent/SKILL.md) | Implement next (or cited) feature vs REQ/wiki/RUB; largest playable change; self-score; PR; stop |
| [`optimize-tests-agent`](optimize-tests-agent/SKILL.md) | Profile and cut suite time; keep ≤5 min coverage / ≤2 min e2e; PR; stop |
| [`refactor-code-agent`](refactor-code-agent/SKILL.md) | Autonomously pick worst arch smell (+ recent-PR hotspots); aggressive themed refactor; PR; stop |
| [`resolve-issue-agent`](resolve-issue-agent/SKILL.md) | Take open `todo` issue; implement + wiki (incl. Design Records when required); after merge → `resolved` −`todo` |
| [`update-pl-data-snapshot`](update-pl-data-snapshot/SKILL.md) | Refresh the PL seed snapshot from one source (ESPN/Sofifa); bump db_version; rebuild + verify the SQLite seed |
| [`review-issue-agent`](review-issue-agent/SKILL.md) | Verify open `resolved` vs evidence/code; close or bounce to `todo` (≤150-word comments) |
| [`ux-playtest-agent`](ux-playtest-agent/SKILL.md) | Desktop live UX playtest (league loop + ≥1 match); wiki Evidence; file issues; no code fixes |

## Scaffold

Add new skills under this tree only when the user explicitly asks. Wire Cursor / OpenCode / Grok facades per [`docs/skills.md`](../../docs/skills.md). Keep skills-only PRs separate from code (`skills-isolation`).
