# Data — multi-competition snapshot

The competitions, clubs and players ship as one SQLite database; the match
engine, picker and encyclopedia all read it, so a squad change lands everywhere.

## Files

| Path | Role |
|------|------|
| `data/pl_snapshot.json` | Readable snapshot: competitions, clubs, players, tables, fixtures, figures, `db_version` |
| `data/pl_seed.sqlite` | Shipped seed built from the JSON; `res://`, read-only |
| `data/pl_scoring_envelope.json` | Last-10 PL scoring bands and the frozen 1X2 baseline for Poisson |
| `user://cache/pl_seed_v<N>.sqlite` | Per-version working copy: in-sim stats are written here |

A `db_version` bump replaces the cache and clears in-sim stats.

## Competitions

Eight leagues: England's five linked tiers (`PL`, `CH`, `L1`, `L2`, `NL`), La
Liga (`LL`) and Germany's pair (`BL`, `BL2`) — 172 clubs. Ids are country-stable
(`ENG-MUN1`, `WAL-CAR1`) and player ids are UUIDs, minted once and kept. Rules:
wiki [DR-20261128-16](https://github.com/waigore/footballsim/wiki/dr-20261128-16).

Seven cups and supercups ship beside them: `FAC`, `EFLC`, `CS`, `CDR`, `SCE`,
`DFBP`, `DFLS`. Each carries `kind`, its rounds, entry pool and European slot;
the wiki is their rules source of truth
([Domestic cups](https://github.com/waigore/footballsim/wiki/domestic-cups)).
The pools need 142 **stub** clubs outside the shipped tiers (England 8, Spain
106, Germany 28): identity, colours, a rating band and a synthetic squad, never
licensed data. `competition_member` names each cup's entry round per club.

## Tool

```bash
python tools/pl_snapshot.py seed --competition LL --season 2026
python tools/pl_snapshot.py fetch --source espn --season 2026 --competition all
python tools/pl_snapshot.py remap
python tools/pl_snapshot.py cups --bump-version
python tools/pl_snapshot.py build
python tools/pl_snapshot.py verify
```

- **One source per run.** `seed` creates a league's clubs and squads from ESPN
  rosters; ratings survive a refresh.
- `fetch` rewrites the table, fixtures, identity and season figures.
- `cups` adds the catalogue, stubs, entry pools and frozen 2025/26 priors;
  idempotent, keeps minted ids.
- `build` writes the seed; `verify` checks counts, ids, eleven starters per club,
  every cup entry pool and the version.

Refresh is an agent task:
[`update-pl-data-snapshot`](../.agents/skills/update-pl-data-snapshot/SKILL.md).
Source policy: wiki
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
| `competition`, `club` | Competition identity and rules JSON; club identity, FIFA country, kit, formation, style, `stub`/`tier`/`region` |
| `competition_member` | Club/player ↔ competition membership: league squads and cup entry pools |
| `player` | Identity, shirt, role, ratings, keeper stats, `squad`, `ord` |
| `table_row`, `fixture` | The 2026-27 table at snapshot date and every fixture, each with `competition_id`; `played` marks results already in |
| `season_stat`, `career_stat` | Real-world season and career figures (`-1` = not in the snapshot) |
| `sim_player_stat`, `sim_club_stat` | Footballsim's own record, written after full time |

Reads go through `PLRepository`, keyed by stable ids; `TeamData` stays the
engine-facing facade, so the sim never talks SQL.
