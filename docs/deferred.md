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
| Poisson λ on the last-10 PL scoring envelope | DR-20261125-19; [#172](https://github.com/waigore/footballsim/issues/172) |
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
| Shape pass shares one ball path per pass | DR-20261125-11 (hot-loop partial) |

## Remaining gaps (impact order)

| Rank | Gap | Notes |
|------|-----|-------|
| 1 | Physics engine retune to PL-envelope λ | [#192](https://github.com/waigore/footballsim/issues/192); wiki poisson-model after DR-20261125-19. Model moved; engine chance level still on the old census fit |
| 2 | Native match hot loop | DR-20261123-02 “future tightening” under the 120 s budget. Shape-pass path shared (DR-20261125-11); tick still GDScript |

## Next pick

**Physics engine retune to PL-envelope λ** — restore physics↔Poisson agreement after
the model landed on the last-10 PL envelope. Move the engine only
([#192](https://github.com/waigore/footballsim/issues/192)); leave λ alone. Native
hot loop stays rank 2 (P4, not rules).

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
