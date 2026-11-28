# Evaluation rubric — Footballsim

Cite `REQ-*`/`RUB-*` in PRs.

| Source | Role |
|--------|------|
| [Simulation rules (wiki)](https://github.com/waigore/footballsim/wiki) | Mechanics SoT (P2) |
| [`requirements.md`](requirements.md) | Product pillars (`REQ-*`) |
| [`../AGENTS.md`](../AGENTS.md) | Agent entry |

## How to apply

1. Touched pillars (`P1`–`P5`); others **N/A** (≠ pass).
2. Score applicable criteria; pillar then overall.
3. Cite fail IDs.

## Score scale

| Score | Label | Meaning |
|------:|-------|---------|
| 3 | Exemplary | Exceeds; reusable |
| 2 | Meets | Satisfies without material gaps |
| 1 | Partial | Directionally right; blocks done |
| 0 | Fail | Missing, contradicted, harmful |
| — | N/A | Outside this change |

**Pass:** applicable ≥2, none 0 per touched pillar; overall = all touched. Any **0** fails.

## Criteria (pass ≥2)

### P1 — Presentation & immersion

| ID | Pass bar |
|----|----------|
| RUB-P1-01 | 2D-first (`REQ-P1-01`) |
| RUB-P1-02 | Football-world look (`REQ-P1-02`) |
| RUB-P1-03 | Readable intentional art (`REQ-P1-03`) |
| RUB-P1-04 | Key actions/transitions animated (`REQ-P1-04`) |
| RUB-P1-05 | Touch + mouse/keyboard (`REQ-P1-05`) |
| RUB-P1-06 | Music optional; mute/volume (`REQ-P1-06`) |
| RUB-P1-07 | Non-match type comfortable, themed (`REQ-P1-07`) |
| RUB-P1-08 | Entity icons; theme + style (`REQ-P1-08`) |

### P2 — Rules fidelity

| ID | Pass bar |
|----|----------|
| RUB-P2-01 | Matches wiki rules (`REQ-P2-01`) |
| RUB-P2-02 | In-scope rules implemented (`REQ-P2-02`) |
| RUB-P2-03 | Presentation cannot override outcomes (`REQ-P2-03`) |
| RUB-P2-04 | Unit tests; CI (`REQ-P2-04`) |
| RUB-P2-05 | Wiki updated same change (`REQ-P2-05`) |

### P3 — Modular architecture (`arch-lint`)

| ID | Pass bar |
|----|----------|
| RUB-P3-01 | **S:** ≤400/25; shrink-only allowlist; typed params (`REQ-P3-01`) |
| RUB-P3-02 | **I:** no deep `get_node`/`$`; autoloads scoped (`REQ-P3-02`) |
| RUB-P3-03 | **D:** sim/data pure; no ui/view loads; reactive views (`REQ-P3-03`) |
| RUB-P3-04 | Changed `scripts/sim/**` (+rules) with `tests/` (`REQ-P3-04`) |
| RUB-P3-05 | OS APIs only in `scripts/platform/**` (`REQ-P3-05`) |
| RUB-P3-06 | Controls chrome, one Theme, canvas budget (`REQ-P3-06`) |

### P4 — Performance & latency

| ID | Pass bar |
|----|----------|
| RUB-P4-01 | No material hitch (`REQ-P4-01`) |
| RUB-P4-02 | Input ack within ~1–2 frames (`REQ-P4-02`) |
| RUB-P4-03 | Long work never freezes UI (`REQ-P4-03`) |
| RUB-P4-04 | Reasonable imports; no leaks (`REQ-P4-04`) |
| RUB-P4-05 | No known stalls shipped (`REQ-P4-05`) |

### P5 — Usability & agency

| ID | Pass bar |
|----|----------|
| RUB-P5-01 | Clear god-action entry (`REQ-P5-01`) |
| RUB-P5-02 | Choice primary; bookkeeping batched (`REQ-P5-02`) |
| RUB-P5-03 | World actions discoverable (`REQ-P5-03`) |
| RUB-P5-04 | Batch/default/confirm-once chores (`REQ-P5-04`) |
| RUB-P5-05 | State-change ack ~1–2 frames (`REQ-P5-05`) |
| RUB-P5-06 | Juice non-modal/skippable; no hidden outcomes (`REQ-P5-06`) |
| RUB-P5-07 | Phone+tablet↔desktop intent parity (`REQ-P5-07`) |
| RUB-P5-08 | Overflow scrolls on touch + desktop (`REQ-P5-08`) |

## Decision record

```text
Pillars touched: P_
RUB scores: P1… P2… P3… P4… P5… (or N/A)
Overall: PASS | FAIL
Blocking IDs: …
Notes: …
```

## Maintenance

New needs get `REQ-*`+`RUB-*`. Don’t remove IDs—deprecate.
