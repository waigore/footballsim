# High-level requirements — Footballsim

Score with [`rubric.md`](rubric.md). **Rules SoT:** [wiki](https://github.com/waigore/footballsim/wiki). Godot 4.

## Pillars

| ID | Pillar | Intent |
|----|--------|--------|
| P1 | Presentation & immersion | Credible football UI; readable chrome |
| P2 | Rules fidelity | Complete, correct wiki simulation rules |
| P3 | Modular architecture | Composable, testable sim + UI |
| P4 | Performance & latency | Smooth, responsive play and sim |
| P5 | Usability & agency | Efficient god-like interventions; platform parity |

## P1 — Presentation & immersion

- **REQ-P1-01** — 2D primary play; no 3D core loops.
- **REQ-P1-02** — Football / sports-broadcast look (not fantasy/sci-fi).
- **REQ-P1-03** — Readable intentional art—not placeholder-as-final.
- **REQ-P1-04** — Meaningful motion; never hide rules or block input (P4).
- **REQ-P1-05** — Phone, tablet, desktop; no hover-only critical UX; resolution-independent UI.
- **REQ-P1-06** — Optional music; mute/volume; don’t obscure feedback.
- **REQ-P1-07** — Readable UI: contrast, type, density; non-match chrome (menus, settings, league hub/table, calendar, encyclopedia, full-time summary, confirms) reads comfortably and type/chrome scale with the viewport on every platform; match overlay excepted.
- **REQ-P1-08** — Distinct icon per player-facing entity type; shared style; no placeholder/emoji/default.

## P2 — Rules fidelity

- **REQ-P2-01** — Wiki is SoT; undocumented house rules ≠ done.
- **REQ-P2-02** — Wiki domains implemented or out-of-scope for milestone.
- **REQ-P2-03** — UI must not bypass/contradict sim; share engines in tests.
- **REQ-P2-04** — Rules unit-tested; CI coverage gate with real cases.
- **REQ-P2-05** — Behavior changes update wiki same change.

## P3 — Modular architecture (SOLID; `arch-lint`)

- **REQ-P3-01** (**S**) — One domain/module; ≤400/≤25 (allowlist ≤5). Extend (**O**); honor (**L**).
- **REQ-P3-02** (**I**) — Narrow APIs/signals; no undeclared autoloads.
- **REQ-P3-03** (**D**) — Sim/rules without visual nodes; view reads state, emits intents.
- **REQ-P3-04** — Changed `scripts/rules/**` (or sim core) ships `tests/`.
- **REQ-P3-05** — Platform diffs only in `scripts/platform/**`.

## P4 — Performance & latency

- **REQ-P4-01** — Stable framerates; avoid poorly scaling per-frame work.
- **REQ-P4-02** — Input ack in ~1–2 frames; defer heavy work.
- **REQ-P4-03** — Match/season/sim steps must not freeze UI; chunk/async when needed.
- **REQ-P4-04** — Intentional imports; atlases/reuse; no unbounded hot-loop allocs.
- **REQ-P4-05** — Don’t ship known multi-second stalls.

## P5 — Usability & agency

P1 = look; P4 = latency; P5 = agency.

- **REQ-P5-01** — God-like interventions on main surfaces; clear critical entry.
- **REQ-P5-02** — Choice primary; chores batched/deferred.
- **REQ-P5-03** — Competitive / world actions in scope discoverable, not buried.
- **REQ-P5-04** — Chores: batch, default, or confirm-once (not one-by-one).
- **REQ-P5-05** — State-change ack ~1–2 frames (`REQ-P4-02`); never silent.
- **REQ-P5-06** — Juice non-modal/skippable; no hidden outcomes (`REQ-P2-03`); no hitches (`REQ-P4-*`).
- **REQ-P5-07** — Intent parity phone+tablet↔desktop. Allowed: OS chrome, safe areas, `scripts/platform/**`, perf—not weaker mobile.
- **REQ-P5-08** — Overflow scrolls on touch and desktop; nothing stranded below the fold.

## Non-goals

Club-manager career mode; licensed data beyond the shipped 2026-27 PL/LL/BL/BL2 snapshots ([DR-20261123-01](https://github.com/waigore/footballsim/wiki/dr-20261123-01)); photoreal/3D primary; desktop-only mobile.
