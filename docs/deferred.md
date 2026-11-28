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
| Poisson / Dixon–Coles; λ envelope; finishing | `poisson_model.gd`; DR-20261122-04 / 24-08 / 25-19 / 26-07/08 |
| PL + English pyramid + LL + German pair | `data/`; DR-20261123-01 / 13 / 17 |
| Season saves, calendar, Continue/watch | `league_season.gd`; DR-20261124-01 / 06 |
| Multi-league save; play-offs; German Relegation | DR-20261126-10 / 14 / 17; [#185](https://github.com/waigore/footballsim/issues/185) |
| System sheet; report packs; non-match type scale | DR-20261124-07 / 04 / 03 |
| Live `tempo`; woodwork; interceptions; momentum | DR-20261122-02 / 25-01 / 02 |
| Whistle goals; roundup club names; encyclopedia season | DR-20261125-04 / 07 / 08 |
| Teams of Interest stay on Watch | DR-20261125-09; [#104](https://github.com/waigore/footballsim/issues/104) |
| Shape-pass shared path; competition hubs; match billing | DR-20261125-11 / 26-01 / 26-06 |
| Phone tap ≥44 dp; match `SKIP` to whistle | DR-20261128-02 / 03 / 05 |
| Club country ids + player UUIDs; watched assist row | DR-20261128-16 / 19 |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Italian Serie A + Serie B pyramid | Rules [DR-20261128-18](https://github.com/waigore/footballsim/wiki/dr-20261128-18); seed has no `SA`/`SB`; [#420](https://github.com/waigore/footballsim/issues/420)–[#424](https://github.com/waigore/footballsim/issues/424). Unblocks UEFA |
| 2 | Domestic cups and supercups | Rules [DR-20261128-17](https://github.com/waigore/footballsim/wiki/dr-20261128-17); no `league_cup_*` yet; [#455](https://github.com/waigore/footballsim/issues/455)–[#459](https://github.com/waigore/footballsim/issues/459). ENG/ESP/GER now; Italy with #420 |
| 3 | Native match hot loop | DR-20261123-02 under the 120 s budget; tick still GDScript |

## Next pick

**Italian pyramid** ([#420](https://github.com/waigore/footballsim/issues/420)) — unblocks UEFA and Italian cups.

## Out of scope / blocked

| Item | Why |
|------|-----|
| UEFA club competitions (UCL/UEL/UECL) | Rules accepted ([DR-20261128-15](https://github.com/waigore/footballsim/wiki/dr-20261128-15); [#434](https://github.com/waigore/footballsim/issues/434)); **blocked** on Italy ([#420](https://github.com/waigore/footballsim/issues/420) / [#433](https://github.com/waigore/footballsim/issues/433)) |
| Club-manager career; player tactics | Product non-goal; Match playable-slice Out |
| Transfers, finances, training, second season, mid-season refresh | Season Out of scope (v1); DR-20261124-01 |
| VAR; weather; referee outcome bias | Match playable-slice Out |
| Concussion subs; extra injury stoppage beyond added-time | Substitutions Out; DR-20261122-05 |
| Licensed data beyond English pyramid, La Liga, German pair | requirements Non-goals; DR-20261123-01 (Italy widens with #420) |
| Match HUD under the non-match type rule | DR-20261124-03 |
| Photoreal / 3D primary | requirements Non-goals |
| Serie C; German-style Relegation for Italy | Season Out of scope |
