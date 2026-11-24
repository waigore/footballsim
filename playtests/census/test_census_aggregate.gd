extends GdToolsTest

## Tier-2 census assert: pools the per-match rows the shard runners wrote and
## hard-gates the agreement between the physics engine and the Poisson model.
## Parent: #31 (physics↔Poisson variance agreement), gate record DR-20261123-02.
##
## For every gated anchor (MCI v BUR, MCI v MCI) it requires the whole fixed grid
## (CENSUS_N matches per anchor, default 32), then asserts:
##
##   1. Goal dispersion: |sample_var − λ| / λ ≤ tolerance(λ, n), the 10%
##      agreement target plus the two-sided 95% sampling allowance at this n
##      (`CensusLib.variance_tolerance`). Poisson is the source of truth. A bare
##      10% band sits under the census's own noise (~27% relative sd of S² at
##      n = 32) and would fail a correctly calibrated engine nearly every run, so
##      the grid asks the question n = 32 can answer honestly: is the engine's
##      dispersion drifting by more than sampling explains? The 10% target itself
##      is evidenced by the big-n manual census (wiki poisson-model).
##   2. Sim cost: every full match finished within the wall-clock budget.
##
## Means and xG are printed for the agreement table but deliberately not gated.
##
## Runs in seconds, so the CI assert job needs no match time of its own. Set
## CENSUS_REQUIRE=1 to fail instead of skipping when no rows exist (the tier-2
## assert job does; a bare local run without shard results just skips).

func test_pooled_census_agrees_with_poisson() -> void:
	var dir := OS.get_environment("CENSUS_DIR").strip_edges()
	if dir.is_empty():
		dir = CensusLib.DEFAULT_RESULTS_DIR
	var expected_n := CensusLib.env_int("CENSUS_N", CensusLib.GRID_N)
	var budget := CensusLib.env_int("CENSUS_MATCH_BUDGET_MS", CensusLib.MATCH_BUDGET_MS)
	var rows := CensusLib.read_rows(dir)
	if rows.is_empty():
		if CensusLib.env_int("CENSUS_REQUIRE", 0) != 1:
			print("CENSUS-SKIP no shard results in %s (run the shard suites first)" % dir)
			return
		assert_true(false, "no census shard results in %s" % dir)
		return
	var pooled := CensusLib.pool_by_anchor(rows)
	var lines: Array[String] = []
	for anchor in CensusLib.ANCHORS.keys():
		var got: Array = pooled.get(anchor, [])
		assert_eq(got.size(), expected_n,
			"%s pooled %d matches across shards; the fixed grid is %d" % [anchor, got.size(), expected_n])
		if got.size() != expected_n:
			# Report what did arrive so a shard that failed still leaves a trail.
			var partial := CensusLib.summarise(str(anchor), got)
			print("CENSUS-PARTIAL %s pooled %d/%d matches  slowest %d ms" % [
				anchor, got.size(), expected_n, partial["slowest_ms"]])
			continue
		var s := CensusLib.summarise(str(anchor), got)
		assert_lte(int(s["slowest_ms"]), budget,
			"%s full match took %d ms (budget %d ms)" % [anchor, s["slowest_ms"], budget])
		assert_lte(s["gap_home"], s["tol_home"],
			"%s home goal variance %.2f is %.0f%% off λ %.2f (band %.0f%% at n=%d: 10%% goal + 95%% sampling allowance)" % [
				anchor, s["var_home"], s["gap_home"] * 100.0, s["lambda_home"], s["tol_home"] * 100.0, s["n"]])
		assert_lte(s["gap_away"], s["tol_away"],
			"%s away goal variance %.2f is %.0f%% off λ %.2f (band %.0f%% at n=%d: 10%% goal + 95%% sampling allowance)" % [
				anchor, s["var_away"], s["gap_away"] * 100.0, s["lambda_away"], s["tol_away"] * 100.0, s["n"]])
		lines.append(CensusLib.summary_line(s))
	# The test runner keeps suite stdout, so the numbers also land in a file the
	# CI log and the wiki table can read.
	var summary_path := OS.get_environment("CENSUS_SUMMARY").strip_edges()
	if summary_path.is_empty():
		summary_path = ".gd-tools/census-summary.txt"
	var f := FileAccess.open(summary_path, FileAccess.WRITE)
	if f != null:
		for line in lines:
			f.store_line(line)
		f.close()
	for line in lines:
		print(line)
