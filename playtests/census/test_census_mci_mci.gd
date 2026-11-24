extends GdToolsTest

## Tier-2 census runner on the even-strength anchor (MCI v MCI). Parent: #31.
## Same contract as the MCI v BUR runner: play one shard of the fixed grid,
## fail fast when a full match breaks the wall-clock budget, and write the
## per-match rows for `test_census_aggregate.gd`, which pools every shard and
## owns the dispersion assert. Means and xG are logged, not gated. Tier-2 only.

const ANCHOR := "mci_mci"

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
