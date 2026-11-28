# Data — multi-competition snapshot

The competitions, clubs and players ship as one SQLite database; the match
engine, fixture picker and encyclopedia all read it, so a squad change lands
everywhere.

## Files

| Path | Role |
|------|------|
| `data/pl_snapshot.json` | Readable snapshot: competitions, clubs, players, tables, fixtures, season/career figures, `db_version` |
| `data/pl_seed.sqlite` | Shipped seed built from the JSON; `res://` and read-only |
| `data/pl_scoring_envelope.json` | Last-10 PL scoring bands and the frozen pre-tune 1X2 baseline for the Poisson calibration |
| `user://cache/pl_seed_v<N>.sqlite` | Per-version working copy: in-sim stats are written here |

`PLDatabase` copies the seed into the cache on first use and drops older copies,
so a `db_version` bump replaces the cache and clears in-sim stats (the sim
ledger belongs to one snapshot).

## Competitions

Eight competitions: England's five linked tiers (`PL`, `CH`, `L1`, `L2`, `NL`),
La Liga (`LL`) and Germany's pair (`BL`, `BL2`) — 172 clubs. Every club id is
country-stable (`ENG-MUN1`, `WAL-CAR1`) and every player id is a UUID; both are
minted once and kept, so promotion and roster refreshes never rewrite identity.
Abbreviations stay display-only; a Welsh club in the English pyramid reads
`WAL-`. Rules: wiki [DR-20261128-16](https://github.com/waigore/footballsim/wiki/dr-20261128-16).

Lower tiers play 24 clubs over 46 matchdays, German tiers 18 over 34; auto-sim
reuses the PL envelope.

## Tool

```bash
python tools/pl_snapshot.py seed --competition LL --season 2026
python tools/pl_snapshot.py fetch --source espn --season 2026 --competition all
python tools/pl_snapshot.py remap
python tools/pl_snapshot.py build
python tools/pl_snapshot.py verify
```

- **One source per run.** A refresh never mixes sources.
- `seed` creates a competition's clubs and squads from ESPN rosters the first
  time a league ships (real clubs, role-based ratings). Ratings survive a
  refresh.
- `fetch` stamps `snapshot_date`, `season_label` and `source`, and rewrites the
  table, fixtures, player identity and season figures.
- `build` writes the seed; `verify` checks counts, id shapes, uniqueness,
  eleven starters per club and the seed's version.
- Commit both; bump `db_version` whenever content changes.

Refresh is an agent task:
[`update-pl-data-snapshot`](../.agents/skills/update-pl-data-snapshot/SKILL.md).
Source policy: wiki
[DR-20261123-01](https://github.com/waigore/footballsim/wiki/dr-20261123-01).

## Poisson scoring envelope

`data/pl_scoring_envelope.json` carries the last-10 Premier League scoring bands
and the frozen pre-tune win/draw/loss mix: the source of truth for the Poisson λ
and the only gate a constant change has to pass:

```bash
godot --headless --path . --script res://tools/poisson_calibrate.gd
```

The report audits λ for fixed pairings then samples whole seasons, checking
goals, home share, champion goals, blowout rate and 1X2 drift.

## Schema

| Table | Holds |
|-------|-------|
| `metadata` | `db_version`, `schema_version`, `season_label`, `snapshot_date`, `source`, `ratings_source`, `competition_ids` |
| `competition`, `club` | League identity and its rules JSON; club identity, FIFA country, kit colours, formation, style profile |
| `competition_member` | club/player ↔ competition membership, ready for cups and internationals |
| `player` | Identity, shirt number, role, ratings, keeper stats, `squad` (`starter`/`bench`), `ord` |
| `table_row`, `fixture` | The 2026-27 table at snapshot date and every fixture, each with `competition_id`; `played` marks the results already in |
| `season_stat`, `career_stat` | Real-world season and career figures (`-1` = not in the snapshot) |
| `sim_player_stat`, `sim_club_stat` | Footballsim's own record, written after full time |

Reads go through `PLRepository` (`scripts/data/pl_repository.gd`), keyed by
stable ids; `TeamData` stays the engine-facing facade, so the sim never talks
SQL.
