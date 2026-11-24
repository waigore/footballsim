extends GdToolsTest

## Tier-2 census runner: physics engine vs Poisson model on the MCI v IPS
## anchor. Parent: #31 (physics↔Poisson variance agreement).
##
## A full 60 Hz GDScript match costs tens of seconds, so the fixed n = 32 grid
## does not fit one CI job: this suite plays one shard of the grid (CENSUS_SHARD
## of CENSUS_SHARDS, default 0 of 1) and fails fast when a full match breaks the
## wall-clock budget. It writes its per-match rows for
## `test_census_aggregate.gd`, which pools every shard and owns the dispersion
## assert (the 10% agreement target plus the 95% sampling allowance at this n,
## `CensusLib.variance_tolerance`).
##
## Means and xG are logged for diagnosis but deliberately not gated. The grid is
## fixed (SEED0 + i·STRIDE) so the gate is deterministic: a failure means the
## engine's agreement or per-match cost moved, not CI noise. Tier-2 only — never
## selected by PR tier-1 (the impact map keeps census edits on the fast poisson
## suite).

const ANCHOR := "mci_ips"

func test_census_shard_runs_the_grid() -> void:
	var n := CensusLib.env_int("CENSUS_N", CensusLib.GRID_N)
	var shards := maxi(1, CensusLib.env_int("CENSUS_SHARDS", 1))
	var shard := clampi(CensusLib.env_int("CENSUS_SHARD", 0), 0, shards - 1)
	var budget := CensusLib.env_int("CENSUS_MATCH_BUDGET_MS", CensusLib.MATCH_BUDGET_MS)
	var rows := CensusLib.run_shard(ANCHOR, n, shard, shards)
	var worst := CensusLib.slowest(rows)
	# Per-match sim-cost budget: a full headless match may not exceed it.
	assert_gte(rows.size(), 1, "shard %d of %d played no matches" % [shard, shards])
	assert_lte(int(worst["ms"]), budget,
		"full match %d took %d ms (budget %d ms)" % [worst["seed"], worst["ms"], budget])
	var dir := OS.get_environment("CENSUS_OUT").strip_edges()
	var path := CensusLib.write_rows(
		dir if not dir.is_empty() else CensusLib.DEFAULT_RESULTS_DIR, ANCHOR, shard, rows)
	assert_false(path.is_empty(), "shard results could not be written to %s" % dir)
	print("CENSUS-SHARD %s shard %d/%d matches %d slowest %d ms -> %s" % [
		ANCHOR, shard, shards, rows.size(), int(worst["ms"]), path])
