# Deferred

Gaps outside the slice. Refresh via
[`audit-deferred-agent`](../.agents/skills/audit-deferred-agent/SKILL.md).
Rules SoT: [wiki](https://github.com/waigore/footballsim/wiki).

## Already live

Shipped (wiki domains playable):

| Area | Locus |
|------|-------|
| Match lifecycle, open play, restarts, ET/pens | `scripts/sim/`; DR-20261126-12 |
| Added time, injuries, handball, official; body-wide / competition bans | DR-20261122-03; DR-20261128-34; [#492](https://github.com/waigore/footballsim/issues/492) |
| Live tactics + IFAB substitutions | DR-20261122-05; MatchAI |
| Poisson / Dixon–Coles; λ envelope; finishing | `poisson_model.gd`; DR-20261122-04 / 24-08 / 25-19 / 26-07/08 / 28-21 |
| PL + English pyramid + LL + German + Italian pairs | `data/`; DR-20261123-01 / 13 / 17 / 18 |
| Season saves, calendar, Continue/watch; multi-league; play-offs; German Relegation | `league_season.gd`; DR-20261124-01 / 06 / 26-10 / 14 / 17 |
| System sheet; report packs; non-match type scale | DR-20261124-07 / 04 / 03 |
| Live `tempo`; woodwork; interceptions; momentum | DR-20261122-02 / 25-01 / 02 |
| Whistle goals; roundup; encyclopedia; ToI Watch | DR-20261125-04 / 07 / 08 / 09 |
| Shape-pass; hubs; match billing; phone tap; `SKIP` | DR-20261125-11 / 26-01 / 26-06 / 28-02 / 03 / 05 |
| Club ids; player UUIDs; assists; FC cards | DR-20261128-16 / 19 / 20; `fc_ratings.gd` |
| Domestic cups (ENG/ESP/GER/ITA) hubs, watch, draws | DR-20261128-17 / 22; `league_cup_*.gd`; [#455](https://github.com/waigore/footballsim/issues/455)–[#480](https://github.com/waigore/footballsim/issues/480) |
| UEFA data, sim, hub, stages, draws, encyclopedia | DR-20261128-15; `league_uefa_*.gd`; [#435](https://github.com/waigore/footballsim/issues/435)–[#437](https://github.com/waigore/footballsim/issues/437) |
| Multi-season settle, archive, age/retire, NEW SEASON | DR-20261128-30; `scripts/sim/market/`; [#440](https://github.com/waigore/footballsim/issues/440) |
| Contracts + association windows | DR-20261128-32; `MarketContracts` / `MarketWindows`; [#441](https://github.com/waigore/footballsim/issues/441) / [#443](https://github.com/waigore/footballsim/issues/443) |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Transfer market (L3+) | L1–L2 + L4 live; finances → deals → lists open — [#438](https://github.com/waigore/footballsim/issues/438), [#442](https://github.com/waigore/footballsim/issues/442), [#444](https://github.com/waigore/footballsim/issues/444)–[#454](https://github.com/waigore/footballsim/issues/454), [#473](https://github.com/waigore/footballsim/issues/473) |
| 2 | Spanish La Liga 2 pyramid | DR-20261128-33 designed; [#496](https://github.com/waigore/footballsim/issues/496)–[#500](https://github.com/waigore/footballsim/issues/500) |
| 3 | Season-two cup & UEFA fields | Rollover clears drops only — [#506](https://github.com/waigore/footballsim/issues/506), [#481](https://github.com/waigore/footballsim/issues/481); DR-35 |
| 4 | Native match hot loop | DR-20261123-02 under 120 s; tick still GDScript |
| 5 | Cup-tied eligibility | Wiki deferred; needs registration ([#448](https://github.com/waigore/footballsim/issues/448)) |

## Next pick

**Transfer market L3: club finances** ([#442](https://github.com/waigore/footballsim/issues/442); parent [#438](https://github.com/waigore/footballsim/issues/438)).

## Out of scope / blocked

| Item | Why |
|------|-----|
| Club-manager career; player tactics | Product non-goal; Match playable-slice Out |
| Training, live data, mid-season seed refresh | Season Out of scope (v1); DR-20261128-25 / 30 |
| VAR; weather; referee outcome bias | Match playable-slice Out |
| Concussion subs; extra injury stoppage beyond added-time | Substitutions Out; DR-20261122-05 |
| Licensed data beyond English chain and ESP/GER/ITA pairs | Non-goals; DR-20261123-01 / 28-15 / 28-18 / 28-33 (stubs OK) |
| Match HUD under the non-match type rule | DR-20261124-03 |
| Photoreal / 3D primary | requirements Non-goals |
| Serie C; Primera Federación; German-style Relegation for Italy | Season Out of scope |
| UEFA FFP; live FX; player development | Finances/Transfers Out; DR-20261128-24 / 25 / 29 |
