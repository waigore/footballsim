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
| Poisson / Dixon–Coles outcomes | `poisson_model.gd`; DR-20261122-04 |
| Physics↔Poisson finishing + level/gradient | DR-20261124-08; [#33](https://github.com/waigore/footballsim/issues/33) closed |
| Poisson λ on the last-10 PL scoring envelope | DR-20261125-19; [#172](https://github.com/waigore/footballsim/issues/172) |
| PL 2026-27 snapshot + encyclopedia | `data/`; DR-20261123-01 / 05 |
| Season saves, calendar, Continue/watch | `league_season.gd`; DR-20261124-01 / 06 |
| System sheet (Quick Save / Save As / Load / Quit) | DR-20261124-07 |
| Per-goal report playback packs | DR-20261124-04 |
| Non-match type / viewport scale | DR-20261124-03 |
| Live `tempo` on the tactics board | DR-20261122-02; drives play now |
| Woodwork, interceptions, momentum, stored rating | DR-20261125-01 / 02 |
| Whistle card lists the goals that made the score | `goal_sheet`; DR-20261125-04 |
| Roundup scorers name their club | [#125](https://github.com/waigore/footballsim/issues/125); DR-20261125-07 |
| Encyclopedia reads the open season | `league_ledger.gd`; DR-20261125-08 |
| Teams of Interest: followed club's games stay on Watch | `league_interest.gd`; DR-20261125-09; [#104](https://github.com/waigore/footballsim/issues/104) |
| Shape pass shares one ball path per pass | DR-20261125-11 |
| Encyclopedia competition hubs + index | `pl_competitions.gd`; DR-20261126-01; [#190](https://github.com/waigore/footballsim/issues/190) |
| Engine priced onto λ, keeper dive, fixture openness | DR-20261126-07 / 08; [#213](https://github.com/waigore/footballsim/pull/213), [#221](https://github.com/waigore/footballsim/pull/221), [#225](https://github.com/waigore/footballsim/pull/225); [#192](https://github.com/waigore/footballsim/issues/192) |
| One competition per match; places as ordinals | `match_billing.gd`; DR-20261126-06; [#209](https://github.com/waigore/footballsim/issues/209), [#207](https://github.com/waigore/footballsim/issues/207) |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | The weak away side's thin chances | [#192](https://github.com/waigore/footballsim/issues/192). Level closed: n=96 goals +6/−2 and +5/−5% of λ (DR-20261126-08). A dominated side still gets 5–6 shots a match; that is creation, not pricing |
| 2 | Native match hot loop | DR-20261123-02 future tightening under the 120 s budget. Shape-pass shared (DR-20261125-11); tick still GDScript |

## Next pick

**The weak away side's thin chances** — a dominated side takes 5–6 shots a match
where λ implies 6–7; the level itself now sits on λ (n=96). Needs creation
design, not a price cut. Native hot loop stays optional while the census fits
120 s.

## Out of scope / blocked

| Item | Why |
|------|-----|
| Club-manager career; player tactics / XI | Product non-goal; Match playable-slice Out |
| Cups, transfers, finances, training, other leagues, second season in one save, mid-season seed refresh of a save | Season Out of scope (v1); DR-20261124-01. Multi-league (#185–#191) waits on #186 before a deferred row (DR-20261126-01) |
| Extra time, shootouts, VAR; weather on the pitch; referee outcome bias | Match playable-slice Out |
| Concussion subs; extra injury stoppage beyond the added-time formula | Substitutions Out of scope; DR-20261122-05 |
| Licensed data beyond the shipped PL snapshot | requirements Non-goals; DR-20261123-01 |
| Match HUD under the non-match type rule | DR-20261124-03 |
| Photoreal / 3D primary | requirements Non-goals |
