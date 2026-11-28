# Deferred

Gaps outside the playable slice. Refresh via
[`audit-deferred-agent`](../.agents/skills/audit-deferred-agent/SKILL.md).
Rules SoT: [wiki](https://github.com/waigore/footballsim/wiki).

## Already live

Shipped (wiki domains playable; DRs accepted):

| Area | Locus |
|------|-------|
| Match lifecycle, open play, restarts | `scripts/sim/`; wiki Match |
| Added time, injuries, handball, official | DR-20261122-03 |
| Live tactics + IFAB substitutions | DR-20261122-05; MatchAI |
| Extra time + pens when a winner is required | DR-20261126-12 |
| Poisson / Dixon–Coles outcomes | `poisson_model.gd`; DR-20261122-04 |
| Physics↔Poisson finishing | DR-20261124-08; [#33](https://github.com/waigore/footballsim/issues/33) closed |
| Poisson λ on the last-10 PL envelope | DR-20261125-19; [#172](https://github.com/waigore/footballsim/issues/172) |
| Engine λ, keeper dive, openness | DR-20261126-07/08; [#192](https://github.com/waigore/footballsim/issues/192) closed |
| PL + English pyramid + LL + German pair | `data/`; DR-20261123-01 / 13 / 17 |
| Season saves, calendar, Continue/watch | `league_season.gd`; DR-20261124-01 / 06 |
| Multi-league save; play-offs; German Relegation | DR-20261126-10 / 14 / 17; [#185](https://github.com/waigore/footballsim/issues/185) |
| System sheet (Quick Save / Save As / Load / Quit) | DR-20261124-07 |
| Per-goal report playback packs | DR-20261124-04 |
| Non-match type / viewport scale | DR-20261124-03 |
| Live `tempo` on the tactics board | DR-20261122-02; drives play now |
| Woodwork, interceptions, momentum, stored rating | DR-20261125-01 / 02 |
| Whistle card lists the goals | `goal_sheet`; DR-20261125-04 |
| Roundup scorers name their club | [#125](https://github.com/waigore/footballsim/issues/125); DR-20261125-07 |
| Encyclopedia reads the open season | `league_ledger.gd`; DR-20261125-08 |
| Teams of Interest: followed games stay on Watch | `league_interest.gd`; DR-20261125-09; [#104](https://github.com/waigore/footballsim/issues/104) |
| Shape pass shares one ball path per pass | DR-20261125-11 |
| Encyclopedia competition hubs + index | `pl_competitions.gd`; DR-20261126-01; [#190](https://github.com/waigore/footballsim/issues/190) |
| One competition per match; places as ordinals | `match_billing.gd`; DR-20261126-06; [#209](https://github.com/waigore/footballsim/issues/209), [#207](https://github.com/waigore/footballsim/issues/207) |
| Phone tap targets ≥44 dp | DR-20261128-02 / 03; [#369](https://github.com/waigore/footballsim/issues/369) |
| Match `SKIP` runs on to the next whistle | DR-20261128-05; [#381](https://github.com/waigore/footballsim/issues/381) |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Native match hot loop | DR-20261123-02 future tightening under the 120 s budget. Shape-pass shared (DR-20261125-11); tick still GDScript |

## Next pick

**Native match hot loop** (DR-20261123-02).

## Out of scope / blocked

| Item | Why |
|------|-----|
| Club-manager career; player tactics / XI | Product non-goal; Match playable-slice Out |
| Cups, transfers, finances, training, second season in one save, mid-season seed refresh of a save | Season Out of scope (v1); DR-20261124-01 |
| VAR; weather on the pitch; referee outcome bias | Match playable-slice Out |
| Concussion subs; extra injury stoppage beyond the added-time formula | Substitutions Out of scope; DR-20261122-05 |
| Licensed data beyond the shipped English pyramid (PL–National League), La Liga and German pair snapshots | requirements Non-goals; DR-20261123-01 |
| Match HUD under the non-match type rule | DR-20261124-03 |
| Photoreal / 3D primary | requirements Non-goals |
