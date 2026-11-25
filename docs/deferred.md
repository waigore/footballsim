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
| Physics↔Poisson finishing + level/gradient | DR-20261124-08; [#33](https://github.com/waigore/footballsim/issues/33) closed; census green |
| PL 2026-27 snapshot + encyclopedia | `data/`; DR-20261123-01 / 05 |
| God-mode season saves, calendar, Continue/watch | `league_season.gd`; DR-20261124-01 / 06 |
| System sheet (Quick Save / Save As / Load / Quit) | DR-20261124-07 |
| Per-goal report playback packs | DR-20261124-04 |
| Non-match type / viewport scale | DR-20261124-03 |
| Live `tempo` on the tactics board | unused in DR-20261122-02; drives play now |
| Woodwork, interceptions, momentum, stored rating | DR-20261125-01; momentum on the broadcast stats card (DR-20261125-02) |
| Whistle card lists the goals that made the score | `goal_sheet`; DR-20261125-04 |
| Roundup scorers name their club, in minute order | [#125](https://github.com/waigore/footballsim/issues/125); DR-20261125-07 |
| Encyclopedia reads the open season (table, results, scorers, player lines) | `league_ledger.gd`; DR-20261125-08 |
| Teams of Interest: a followed club's games stay on Watch, gold names | `league_interest.gd`; DR-20261125-09; [#104](https://github.com/waigore/footballsim/issues/104) |
| Encyclopedia competition hubs + index | `pl_competitions.gd`; DR-20261126-01; [#190](https://github.com/waigore/footballsim/issues/190) |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Native match hot loop | DR-20261123-02 “future tightening” under the 120 s full-match budget. The shape pass now shares one ball path per pass (DR-20261125-11); the tick itself is still GDScript |

## Next pick

**Native match hot loop** — only ranked gap left; cuts full-match wall clock under
the census budget without changing the gated agreement story. The repeated
per-body work in the shape pass is gone ([DR-20261125-11](https://github.com/waigore/footballsim/wiki/dr-20261125-11));
what remains is the tick body's own GDScript cost.

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
