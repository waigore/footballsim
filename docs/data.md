# Data — Premier League snapshot

The league, its clubs and its players ship as one SQLite database. The match
engine, the fixture picker and the encyclopedia all read it, so a squad change
lands everywhere at once.

## Files

| Path | Role |
|------|------|
| `data/pl_snapshot.json` | Readable snapshot: clubs, players, table, fixtures, season/career figures, `db_version` |
| `data/pl_seed.sqlite` | Shipped seed built from the JSON; `res://` and read-only |
| `user://cache/pl_seed_v<N>.sqlite` | Per-version working copy: in-sim stats are written here |

`PLDatabase` copies the seed into the cache on first use and deletes copies from
older seeds, so a `db_version` bump both replaces the cache and clears in-sim
stats (accepted: the sim ledger belongs to one snapshot).

## Tool

```bash
python tools/pl_snapshot.py fetch --source espn --season 2026 --bump-version
python tools/pl_snapshot.py build
python tools/pl_snapshot.py verify
```

- **One source per run.** ESPN is preferred; a refresh never mixes sources.
  Player ratings are the game's own dataset and survive a league refresh.
- `fetch` stamps `snapshot_date`, `season_label` and `source`, and rewrites the
  table, fixtures, player identity (age/nationality/DOB) and season figures.
- `build` writes the seed; `verify` checks counts, unique ids, eleven starters
  per club and that the seed's version matches the JSON.
- Commit both files together. Bump `db_version` whenever the content changes.

Refreshing the snapshot is an agent workflow: see the
[`update-pl-data-snapshot`](../.agents/skills/update-pl-data-snapshot/SKILL.md)
project skill. Design rationale and the source policy: wiki
[DR-20261123-01](https://github.com/waigore/footballsim/wiki/dr-20261123-01).

## Schema

| Table | Holds |
|-------|-------|
| `metadata` | `db_version`, `schema_version`, `season_label`, `snapshot_date`, `source`, `ratings_source` |
| `competition`, `club` | League identity; club identity, kit colours, formation, style profile |
| `player` | Identity, shirt number, role, ratings, keeper stats, `squad` (`starter`/`bench`), `ord` |
| `table_row`, `fixture` | The 2026-27 table at snapshot date and every fixture; `played` marks the results already in |
| `season_stat`, `career_stat` | Real-world season and career figures (`-1` = not in the snapshot) |
| `sim_player_stat`, `sim_club_stat` | Footballsim's own record, written after full time |

Reads go through `PLRepository` (`scripts/data/pl_repository.gd`); `TeamData`
stays the engine-facing facade, so the sim never talks SQL.
