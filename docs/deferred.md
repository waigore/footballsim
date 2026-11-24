# Deferred

Ranked gaps outside the current playable slice. Agents refresh via
[`audit-deferred-agent`](../.agents/skills/audit-deferred-agent/SKILL.md).
Rules SoT: [wiki](https://github.com/waigore/footballsim/wiki).

## Already live

Former gaps now shipped (wiki domains playable; DRs accepted):

| Area | Locus |
|------|-------|
| Match lifecycle, open play, restarts | `scripts/sim/`, wiki Match |
| Added time, injuries, handball, pitch official | DR-20261122-03 |
| Live tactics + IFAB substitutions | DR-20261122-05; MatchAI |
| Poisson / Dixon–Coles outcomes | `poisson_model.gd`; DR-20261122-04 |
| PL 2026-27 snapshot + encyclopedia | `data/`; DR-20261123-01 / 05 |
| God-mode season saves, calendar, Continue/watch | `league_season.gd`; DR-20261124-01 / 06 |
| Per-goal report playback packs | DR-20261124-04 |
| Non-match type / viewport scale | DR-20261124-03 |
| Live `tempo` on the tactics board | unused in DR-20261122-02; drives play now |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Physics↔Poisson level and strength gradient | Wiki [poisson-model](https://github.com/waigore/footballsim/wiki/poisson-model) + [#33](https://github.com/waigore/footballsim/issues/33); [#111](https://github.com/waigore/footballsim/pull/111) prices chance quality from ratings — census re-check still open |
| 2 | Match summary schema stubs | `momentum`, `xt_gain`, `woodwork`, `interceptions`, stored `rating` declared on Match; never written |
| 3 | Native match hot loop | DR-20261123-02 “future tightening” under the 120 s full-match budget |

## Next pick

**Physics↔Poisson level and strength gradient** — finishes P2 agreement after
#111 so auto-sim and watched physics stay trustworthy on the same ratings.

## Out of scope / blocked

| Item | Why |
|------|-----|
| Club-manager career; player tactics / XI | Product non-goal; Match playable-slice Out |
| Cups, transfers, finances, training, other leagues, second season in one save, mid-season seed refresh of a save | Season Out of scope (v1); DR-20261124-01 |
| Extra time, shootouts, VAR; weather on the pitch; referee outcome bias | Match playable-slice Out |
| Concussion subs; extra injury stoppage beyond the added-time formula | Substitutions Out of scope; DR-20261122-05 |
| Licensed data beyond the shipped PL snapshot | requirements Non-goals; DR-20261123-01 |
| Match HUD under the non-match type rule | DR-20261124-03 |
| Photoreal / 3D primary | requirements Non-goals |
