# Requirements — Footballsim

Score with [`rubric.md`](rubric.md). **Rules SoT:** [wiki](https://github.com/waigore/footballsim/wiki).

## Pillars

| ID | Pillar | Intent |
|----|--------|--------|
| P1 | Presentation & immersion | Credible, readable UI |
| P2 | Rules fidelity | Complete, correct wiki rules |
| P3 | Modular architecture | Composable, testable sim + UI |
| P4 | Performance & latency | Smooth, responsive play |
| P5 | Usability & agency | God-like actions; parity |

## P1 Presentation & immersion

- **REQ-P1-01** — 2D primary play; no 3D core loops.
- **REQ-P1-02** — Football / sports-broadcast look (not fantasy/sci-fi).
- **REQ-P1-03** — Intentional art—not placeholder-as-final.
- **REQ-P1-04** — Meaningful motion; never hide rules or block input (P4).
- **REQ-P1-05** — Phone, tablet, desktop; no hover-only critical UX; resolution-independent.
- **REQ-P1-06** — Optional music; mute/volume; don’t obscure feedback.
- **REQ-P1-07** — Readable UI: contrast, type, density; non-match chrome (menus, settings, league hub/table, calendar, encyclopedia, confirms) reads comfortably off one Theme; match overlay excepted.
- **REQ-P1-08** — Distinct icon per entity type; shared style; no placeholder/emoji/default.

## P2 Rules fidelity

- **REQ-P2-01** — Wiki is SoT; undocumented rules ≠ done.
- **REQ-P2-02** — Wiki domains implemented or out of scope.
- **REQ-P2-03** — UI never bypasses/contradicts sim; share engines in tests.
- **REQ-P2-04** — Rules unit-tested; CI coverage gate with real cases.
- **REQ-P2-05** — Behavior changes update wiki same change.

## P3 Modular architecture (SOLID; `arch-lint`)

- **REQ-P3-01** (**S**) — One domain/module; ≤400 lines/≤25 methods (allowlist ≤5); extend, honor.
- **REQ-P3-02** (**I**) — Narrow APIs/signals; autoloads declared + consumer-scoped.
- **REQ-P3-03** (**D**) — Sim/data RefCounted-only; no load of ui/view/scenes; views subscribe to state, never pull from a screen node.
- **REQ-P3-04** — Changed `scripts/sim/**` (or rules) ships `tests/`.
- **REQ-P3-05** — Platform diffs only in `scripts/platform/**`.
- **REQ-P3-06** — Controls-first non-match chrome from `ui/components/` widgets; one Theme `.tres` is the palette SoT; canvas only in HUD and pitch under a fixed CI budget.

## P4 Performance & latency

- **REQ-P4-01** — Stable framerates; avoid poorly scaling per-frame work.
- **REQ-P4-02** — Input ack in ~1–2 frames; defer heavy work.
- **REQ-P4-03** — Match/season/sim steps never freeze UI; chunk/async.
- **REQ-P4-04** — Intentional imports; atlases/reuse; no hot-loop allocs.
- **REQ-P4-05** — No known multi-second stalls.

## P5 Usability & agency

- **REQ-P5-01** — God-like interventions on main surfaces; clear critical entry.
- **REQ-P5-02** — Choice first; chores batched/deferred.
- **REQ-P5-03** — World actions discoverable, not buried.
- **REQ-P5-04** — Chores: batch, default, or confirm-once (not one-by-one).
- **REQ-P5-05** — State-change ack ~1–2 frames (`REQ-P4-02`); never silent.
- **REQ-P5-06** — Juice non-modal/skippable; no hidden outcomes (`REQ-P2-03`) or hitches (`REQ-P4-*`).
- **REQ-P5-07** — Intent parity phone+tablet↔desktop; only OS chrome, safe areas, `scripts/platform/**` and perf differ.
- **REQ-P5-08** — Overflow scrolls on touch and desktop; nothing below the fold.

## Non-goals

Club-manager career; licensed data beyond the English chain and Spanish, German and Italian pairs ([DR-20261123-01](https://github.com/waigore/footballsim/wiki/dr-20261123-01), [DR-20261128-18](https://github.com/waigore/footballsim/wiki/dr-20261128-18), [DR-20261128-33](https://github.com/waigore/footballsim/wiki/dr-20261128-33)) — cup and UEFA stubs are identity plus a rating band ([DR-20261128-15](https://github.com/waigore/footballsim/wiki/dr-20261128-15)); photoreal/3D; desktop-only mobile.
