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
| Poisson / Dixon–Coles; λ envelope; finishing | `poisson_model.gd`; DR-20261122-04 / 24-08 / 25-19 / 26-07/08 / 28-21 |
| PL + English pyramid + LL + German + Italian pairs | `data/`; DR-20261123-01 / 13 / 17 / 18 |
| Season saves, calendar, Continue/watch | `league_season.gd`; DR-20261124-01 / 06 |
| Multi-league save; play-offs; German Relegation | DR-20261126-10 / 14 / 17; [#185](https://github.com/waigore/footballsim/issues/185) |
| System sheet; report packs; non-match type scale | DR-20261124-07 / 04 / 03 |
| Live `tempo`; woodwork; interceptions; momentum | DR-20261122-02 / 25-01 / 02 |
| Whistle goals; roundup names; encyclopedia | DR-20261125-04 / 07 / 08 |
| Teams of Interest stay on Watch | DR-20261125-09; [#104](https://github.com/waigore/footballsim/issues/104) |
| Shape-pass path; competition hubs; match billing | DR-20261125-11 / 26-01 / 26-06 |
| Phone tap ≥44 dp; match `SKIP` to whistle | DR-20261128-02 / 03 / 05 |
| Club country ids; player UUIDs; watched assists | DR-20261128-16 / 19 |
| FC-derived cards; Simplified/Full attributes | DR-20261128-20; `fc_ratings.gd` |
| Domestic cups (ENG/ESP/GER) hubs, watch, draws | DR-20261128-17 / 22; `league_cup_*.gd`; [#455](https://github.com/waigore/footballsim/issues/455)–[#459](https://github.com/waigore/footballsim/issues/459) |
| UEFA data + sim path (UCL/UEL/UECL) | DR-20261128-15; `league_uefa_*.gd`; [#435](https://github.com/waigore/footballsim/issues/435)–[#436](https://github.com/waigore/footballsim/issues/436) |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Transfer market + multi-season | Rules landed ([#439](https://github.com/waigore/footballsim/issues/439)); no `scripts/sim/market/` — [#440](https://github.com/waigore/footballsim/issues/440)–[#454](https://github.com/waigore/footballsim/issues/454), [#473](https://github.com/waigore/footballsim/issues/473) |
| 2 | Europe UX (hub, stages, draws, wizard) | Sim playable; surfaces missing — [#437](https://github.com/waigore/footballsim/issues/437) |
| 3 | Italian cups (Coppa Italia, Supercoppa) | Wiki names them; no `CI`/`SCI` seed — [#480](https://github.com/waigore/footballsim/issues/480) |
| 4 | Native match hot loop | DR-20261123-02 under 120 s; tick still GDScript |
| 5 | Cup-tied eligibility | Transfers deferred; needs market registration |

## Next pick

**Transfer market + multi-season** ([#438](https://github.com/waigore/footballsim/issues/438) / [#440](https://github.com/waigore/footballsim/issues/440)).

## Out of scope / blocked

| Item | Why |
|------|-----|
| Club-manager career; player tactics | Product non-goal; Match playable-slice Out |
| Training, live data, mid-season seed refresh | Season Out of scope (v1); DR-20261128-25 / 30 |
| VAR; weather; referee outcome bias | Match playable-slice Out |
| Concussion subs; extra injury stoppage beyond added-time | Substitutions Out; DR-20261122-05 |
| Licensed data beyond ENG/ESP/GER/ITA chains | Non-goals; DR-20261123-01 / 28-15 / 28-18 (stubs OK) |
| Match HUD under the non-match type rule | DR-20261124-03 |
| Photoreal / 3D primary | requirements Non-goals |
| Serie C; German-style Relegation for Italy | Season Out of scope |
| UEFA FFP; live FX; player development | Finances/Transfers Out; DR-20261128-24 / 25 / 29 |
