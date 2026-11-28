# Data — multi-competition snapshot

The competitions, clubs and players ship as one SQLite database; the match
engine, fixture picker and encyclopedia all read it.

## Files

| Path | Role |
|------|------|
| `data/pl_snapshot.json` | Readable snapshot: competitions, clubs, players, tables, fixtures, `db_version` |
| `data/pl_seed.sqlite` | Shipped seed built from the JSON; `res://` and read-only |
| `data/fc_sheet.csv` | Sofifa EA FC 26 sheet: sub-stats and card extras |
| `data/fc_ratings.json` | Face weights, positional overall weights, synthesis |
| `data/pl_scoring_envelope.json` | Last-10 PL scoring bands and the frozen pre-tune 1X2 baseline |
| `user://cache/pl_seed_v<N>.sqlite` | Per-version working copy: in-sim stats live here |

`PLDatabase` copies the seed into the cache and drops older copies, so a
`db_version` bump replaces the cache and clears in-sim stats (the ledger belongs
to one snapshot).

## Competitions

Eight competitions: England's five linked tiers (`PL`, `CH`, `L1`, `L2`, `NL`),
La Liga (`LL`) and Germany's pair (`BL`, `BL2`) — 172 clubs. Club ids are
country-stable (`ENG-MUN1`) and player ids are UUIDs, minted once, so promotion
and roster refreshes never rewrite identity. Abbreviations stay display-only:
[DR-20261128-16](https://github.com/waigore/footballsim/wiki/dr-20261128-16).

Lower tiers play 24 clubs over 46 matchdays, German tiers 18 over 34; auto-sim
reuses the PL envelope.

## Tool

```bash
python tools/pl_snapshot.py seed --competition LL --season 2026
python tools/pl_snapshot.py fetch --source espn --season 2026 --competition all
python tools/pl_snapshot.py remap
python tools/pl_snapshot.py ratings --bump-version
python tools/pl_snapshot.py build
python tools/pl_snapshot.py verify
```

- **One source per run.**
- `seed` creates a competition's clubs and squads from ESPN rosters the first
  time a league ships; ratings survive a refresh.
- `ratings` remaps every squad from `data/fc_sheet.csv`, synthesizes the rest, and
  derives every face bar and overall through `fc_ratings`, offline. Its gate
  holds the PL, La Liga and Bundesliga XIs to a match rate.
- `fetch` stamps `snapshot_date`, `season_label` and `source`, then rewrites the
  table, fixtures, identity and season figures.
- `build` writes the seed; `verify` checks counts, id shapes, uniqueness,
  eleven starters, all 34 sub-stats per player, that every stored card
  re-derives from its own sheet, and the seed's version.
- Commit both; bump `db_version` whenever content changes.

Refresh is an agent task:
[`update-pl-data-snapshot`](../.agents/skills/update-pl-data-snapshot/SKILL.md);
source policy wiki
[DR-20261123-01](https://github.com/waigore/footballsim/wiki/dr-20261123-01).

## Poisson scoring envelope

`data/pl_scoring_envelope.json` is the source of truth for λ, and the only gate a
constant change must pass:

```bash
godot --headless --path . --script res://tools/poisson_calibrate.gd
```

## Schema

| Table | Holds |
|-------|-------|
| `metadata` | `db_version`, `schema_version`, `season_label`, `snapshot_date`, `source`, `ratings_source`, `competition_ids` |
| `competition`, `club` | League identity and rules JSON; club identity, FIFA country, kit, formation, style |
| `competition_member` | club/player ↔ competition membership: cup pools and internationals |
| `player` | Identity, role, ratings, keeper stats, `subs` (34-stat sheet), `extras`, `ratings_matched`, `squad`, `ord` |
| `table_row`, `fixture` | The 2026-27 table at snapshot date and every fixture; `played` marks results already in |
| `season_stat`, `career_stat` | Real-world season and career figures (`-1` = absent) |
| `sim_player_stat`, `sim_club_stat` | Footballsim's own record after full time |

Reads go through `PLRepository` (`scripts/data/pl_repository.gd`), keyed by
stable ids; `TeamData` is the engine facade, so the sim never talks SQL. Every
card re-derives from its own `subs` through `FCRatings`; the wiki
[player-attributes](https://github.com/waigore/footballsim/wiki/player-attributes)
page is the formula SoT, and the sim reads face bars only.
