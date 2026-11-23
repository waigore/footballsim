---
name: update-pl-data-snapshot
description: |-
  Refresh the Premier League seed snapshot from exactly one source (ESPN
  preferred, Sofifa otherwise), bump db_version, rebuild the SQLite seed and
  verify it. Use when the league table, fixtures, player identity or real-world
  season figures need updating, or when a new season starts.
---

# Update the PL data snapshot

One source per run, one versioned seed, one commit. The game never talks to the
network: this skill runs at authoring time in the repo.

## Rules

- **One source per dataset.** ESPN is preferred. A Sofifa run rebuilds ratings
  and imports no ESPN league data. Never merge two runs into one snapshot.
- **Ratings belong to the game.** An ESPN refresh updates the table, fixtures,
  identity and season figures; it does **not** rewrite `ovr/pac/...`.
- **Always bump `db_version`** when content changes: the game flushes its cache
  and in-sim stats on a bump (accepted — see [DR-20261123-01]).
- Commit `data/pl_snapshot.json` **and** `data/pl_seed.sqlite` together.
- Never hand-edit the `.sqlite`; it is generated.

## Workflow

1. **Orient.** `git status` clean on a fresh branch; read
   [`docs/data.md`](../../../docs/data.md) for the schema and file roles.
2. **Refresh from one source.**

   ```bash
   python tools/pl_snapshot.py fetch --source espn --season 2025 --bump-version
   ```

   This pulls the final table, all fixtures/results, player identity
   (age / nationality / date of birth) and per-player season + career figures
   from ESPN, and stamps `source`, `season_label` and `snapshot_date`.
   For a new season pass the starting year (`--season 2026` for 2026–27).
3. **Check the diff.** `data/pl_snapshot.json` should show the new table,
   fixtures and figures and an incremented `db_version`. Abort if the source
   changed under you mid-run (mixed seasons) — re-run once rather than patching.
4. **Rebuild and verify.**

   ```bash
   python tools/pl_snapshot.py build
   python tools/pl_snapshot.py verify
   ```

   `verify` fails on a version mismatch, duplicate player ids, a club without
   eleven starters, or a club count that disagrees with the snapshot.
5. **Test.** `gd-tools test tests/test_pl_seed.gd tests/test_pl_stats.gd` plus
   the impacted suite selection (`python tools/select_impacted_tests.py`).
   Snapshot tests assert the season label, the 20-club table, 380 fixtures and
   that every dismissal link resolves.
6. **PR.** Cite the issue; note the source, season, snapshot date and old → new
   `db_version` in the body; say explicitly that ratings were untouched.

## Ratings run (Sofifa)

Only when the game's ability ratings themselves are being refreshed. Keep it a
separate run and a separate commit from an ESPN refresh, and say so in the PR.
There is no automated Sofifa importer yet: a ratings run edits the `player`
rows in `data/pl_snapshot.json` (keeping ids and squads intact), then follows
steps 4–6.

## Output

A versioned seed (`data/pl_seed.sqlite`) with a new `db_version`, built from one
source, verified, tested, and shipped with its readable snapshot.

[DR-20261123-01]: https://github.com/waigore/footballsim/wiki/dr-20261123-01
