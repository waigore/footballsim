# Agent guide — Footballsim

Godot 4 football world simulation for **desktop** (Windows, macOS, Linux) and **mobile** (Android, iOS). Prefer reuse and existing project patterns over new abstractions. Player is god-like (not club manager); sim engines drive outcomes.

## Always refer to

| Doc | Use |
|-----|-----|
| [Simulation rules (wiki)](https://github.com/waigore/footballsim/wiki) | Rules source of truth (P2) |
| [`docs/requirements.md`](docs/requirements.md) | Product pillars P1–P5 (`REQ-*`) |
| [`docs/rubric.md`](docs/rubric.md) | Evaluation gate (`RUB-*`) |
| [`docs/pull-requests.md`](docs/pull-requests.md) | PR base rules (`gh`, required checks) |
| [`docs/android-debug.md`](docs/android-debug.md) | Debug APK via PR into `android-debug` |
| [`docs/skills.md`](docs/skills.md) | Project skills + agent facades |
| [`docs/README.md`](docs/README.md) | Docs index |

## Docs policy

Root and `docs/` Markdown must stay **≤ 500 words** (fenced code excluded). CI `docs-lint` fails over-limit files (`python tools/lint_docs_words.py`). Prefer tables and short bullets; long mechanics go in the wiki.

## Stack

- Engine: Godot 4.7.x · GDScript (typed where practical)
- Scenes: `.tscn` + scripts; logic in scripts / sim modules, composition in scenes
- Tests: [`gd-tools`](https://github.com/mansyar/gd-tools) (`GdToolsTest`); PR **tier 1** impacted suites + **80% patch** coverage (**≤5 min**); **tier 2** every 8h full suite + overall 80%; e2e smoke **≤4 min** — see [`docs/testing.md`](docs/testing.md). Until `project.godot` exists, Godot CI jobs no-op.

## Layout

| Path | Use |
|------|-----|
| `scenes/` | Screens and gameplay scenes |
| `scripts/` | Shared / sim / non-scene scripts |
| `ui/` | UI scenes, themes, components |
| `assets/` | Art, audio, fonts |
| `autoload/` | Allowlisted cross-cutting only (`arch-lint`) |
| `tests/` · `playtests/` | Suite / drives |
| `addons/gd-tools-*` | Vendored gd-tools addons (when added) |

## Conventions

- **Reuse first**; typed GDScript; signals over deep node reach-ins. Scripts ≤400 lines / ≤25 methods; size allowlist ≤5 and shrink-only (`arch-lint`).
- **Sim vs UI**: engines deterministic/seedable and testable without UI; Godot screens stay thin; god-actions are explicit sim inputs.
- **Input**: mouse/keyboard + touch via InputMap actions.
- **UI**: containers + anchors + theme; no fixed pixel layouts; no hover-only critical UX.
- **Exports**: platform diffs isolated; shared core. P3 + static P1 (2D/icons/hover) gated by `arch-lint`.

## Do / don’t

- Do keep scenes focused; guard early; shallow nesting.
- Do open/merge PRs with `gh`; wait for required checks — see [`docs/pull-requests.md`](docs/pull-requests.md).
- Don’t commit `.godot/`, export caches, or local overrides.
- Don’t add plugins/addons without need; don’t hard-code resolutions or OS names in gameplay/sim.
- Don’t bypass, force-merge, or skip required PR checks.
- Don’t build “manage this club” mode or use licensed real-world data unless explicitly asked.

## Project skills

Do **not** create, edit, rename, or delete project skills unless the user **explicitly** asks for a skills change. Scope: `.agents/skills/` (incl. README), facades (`.cursor/skills/`, `.opencode/skill/`, `.grok/skills/`), and `docs/skills.md`. Side edits during other work are banned; CI `skills-isolation` fails code∩skills PRs.

## When unsure

Match neighboring naming, folders, and patterns. Prefer simulation fidelity and a small testable surface over extra layers.
