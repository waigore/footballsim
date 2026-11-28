# Data — multi-competition snapshot

The competitions, clubs and players ship as one SQLite database; the match
engine, picker and encyclopedia all read it, so a squad change lands everywhere.

## Files

| Path | Role |
|------|------|
| `data/pl_snapshot.json` | Readable snapshot: competitions, clubs, players, tables, fixtures, `db_version` |
| `data/pl_seed.sqlite` | Shipped seed built from the JSON; `res://`, read-only |
| `data/fc_sheet.csv` | Sofifa EA FC 26 sheet: sub-stats and card extras |
| `data/fc_ratings.json` | Face weights, positional weights, synthesis |
| `data/pl_scoring_envelope.json` | Last-10 PL scoring bands and the frozen 1X2 baseline for Poisson |
| `user://cache/pl_seed_v<N>.sqlite` | Per-version working copy: in-sim stats are written here |

A `db_version` bump replaces the cache and clears in-sim stats.

## Competitions

Eight leagues: England's five linked tiers (`PL`, `CH`, `L1`, `L2`, `NL`), La
Liga (`LL`) and Germany's pair (`BL`, `BL2`) — 172 clubs. Ids are country-stable
(`ENG-MUN1`, `WAL-CAR1`) and player ids are UUIDs, minted once and kept. Rules:
wiki [DR-20261128-16](https://github.com/waigore/footballsim/wiki/dr-20261128-16).

Seven cups and supercups ship beside them: `FAC`, `EFLC`, `CS`, `CDR`, `SCE`,
`DFBP`, `DFLS`. The wiki is their rules source of truth
([Domestic cups](https://github.com/waigore/footballsim/wiki/domestic-cups)).
Their pools need 142 **stub** clubs outside the shipped tiers (England 8, Spain
106, Germany 28): identity, colours, a tier band and a synthetic squad. A stub
never matches the sheet — its invented names would pair with real players.

## Tool

```bash
python tools/pl_snapshot.py seed --competition LL --season 2026
python tools/pl_snapshot.py fetch --source espn --season 2026 --competition all
python tools/pl_snapshot.py remap
python tools/pl_snapshot.py cups --bump-version
python tools/pl_snapshot.py ratings --bump-version
python tools/pl_snapshot.py build
python tools/pl_snapshot.py verify
```

- **One source per run.** `seed` creates a league's clubs and squads from ESPN
  rosters; ratings survive a refresh.
- `fetch` rewrites the table, fixtures, identity and season figures.
- `cups` adds the catalogue, stubs, entry pools and frozen priors.
- `ratings` remaps squads from `data/fc_sheet.csv`, synthesizes the rest and
  derives every card, offline.
- `build` writes the seed; `verify` checks counts, ids, eleven starters per club,
  cup entry pools, all 34 sub-stats, that every stored card re-derives, and the
  version.

Refresh is an agent task:
[`update-pl-data-snapshot`](../.agents/skills/update-pl-data-snapshot/SKILL.md);
source policy wiki
[DR-20261123-01](https://github.com/waigore/footballsim/wiki/dr-20261123-01).

## Poisson scoring envelope

`data/pl_scoring_envelope.json` carries the scoring bands and the frozen
win/draw/loss mix: the source of truth for the Poisson λ.

```bash
godot --headless --path . --script res://tools/poisson_calibrate.gd
```

The report audits λ for fixed pairings then samples whole seasons.

## Schema

| Table | Holds |
|-------|-------|
| `metadata` | `db_version`, `schema_version`, `season_label`, `snapshot_date`, `source`, `ratings_source`, `competition_ids` |
| `competition`, `club` | Competition rules JSON; club identity, kit, formation, style, `stub`/`tier`/`region` |
| `competition_member` | Club/player ↔ competition membership: league squads and cup entry pools |
| `player` | Identity, role, ratings, keeper stats, `subs`, `extras`, `ratings_matched`, `squad`, `ord` |
| `table_row`, `fixture` | The 2026-27 table at snapshot date and every fixture, each with `competition_id` |
| `season_stat`, `career_stat` | Real-world figures (`-1` = not in the snapshot) |
| `sim_player_stat`, `sim_club_stat` | Footballsim's own record, written after full time |

Reads go through `PLRepository`, keyed by stable ids; `TeamData` stays the
engine-facing facade, so the sim never talks SQL. Every card re-derives from its
own `subs` through `FCRatings`; the wiki
[player-attributes](https://github.com/waigore/footballsim/wiki/player-attributes)
page is the formula SoT, and the sim reads face bars only.
