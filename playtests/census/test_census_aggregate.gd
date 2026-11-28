extends GdToolsTest


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
	var complete := 0
	for anchor in CensusLib.ANCHORS.keys():
		var got: Array = pooled.get(anchor, [])
		assert_eq(got.size(), expected_n,
			"%s pooled %d matches across shards; the fixed grid is %d" % [anchor, got.size(), expected_n])
		if got.size() != expected_n:
			var partial := CensusLib.summarise(str(anchor), got)
			print("CENSUS-PARTIAL %s pooled %d/%d matches  slowest %d ms" % [
				anchor, got.size(), expected_n, partial["slowest_ms"]])
			continue
		complete += 1
		var s := CensusLib.summarise(str(anchor), got)
		assert_lte(int(s["slowest_ms"]), budget,
			"%s full match took %d ms (budget %d ms)" % [anchor, s["slowest_ms"], budget])
		assert_lte(s["gap_home"], s["tol_home"],
			"%s home goal variance %.2f is %.0f%% off λ %.2f (band %.0f%% at n=%d: 10%% goal + 95%% sampling allowance)" % [
				anchor, s["var_home"], s["gap_home"] * 100.0, s["lambda_home"], s["tol_home"] * 100.0, s["n"]])
		assert_lte(s["gap_away"], s["tol_away"],
			"%s away goal variance %.2f is %.0f%% off λ %.2f (band %.0f%% at n=%d: 10%% goal + 95%% sampling allowance)" % [
				anchor, s["var_away"], s["gap_away"] * 100.0, s["lambda_away"], s["tol_away"] * 100.0, s["n"]])
		assert_lte(s["xg_gap_home"], s["xg_tol_home"],
			"%s home goals %.2f are %.0f%% off displayed xG %.2f (band %.0f%% at n=%d: 10%% target + 95%% sampling allowance)" % [
				anchor, s["mean_home"], s["xg_gap_home"] * 100.0, s["xg_home"], s["xg_tol_home"] * 100.0, s["n"]])
		assert_lte(s["xg_gap_away"], s["xg_tol_away"],
			"%s away goals %.2f are %.0f%% off displayed xG %.2f (band %.0f%% at n=%d: 10%% target + 95%% sampling allowance)" % [
				anchor, s["mean_away"], s["xg_gap_away"] * 100.0, s["xg_away"], s["xg_tol_away"] * 100.0, s["n"]])
		lines.append(CensusLib.summary_line(s))
	assert_eq(complete, CensusLib.ANCHORS.size(), "the fixed grid did not pool every anchor")
	var xg := CensusLib.xg_pooled(pooled)
	assert_gte(int(xg["n"]), 2, "the pooled xG gate read no team matches")
	assert_lte(float(xg["gap"]), float(xg["tol"]),
		"pooled goals %.3f are %.0f%% off displayed xG %.3f (band %.0f%%: 10%% target + 95%% sampling allowance)" % [
			xg["goals"], float(xg["gap"]) * 100.0, xg["xg"], float(xg["tol"]) * 100.0])
	assert_lte(float(xg["blank_rate"]), CensusLib.BLANK_RATE,
		"%.0f%% of the %d sides with xG over %.1f were blanked" % [
			float(xg["blank_rate"]) * 100.0, int(xg["high_xg"]), CensusLib.BLANK_XG])
	lines.append("CENSUS-POOLED n=%d  goals %.2f  xG %.2f  gap %.1f%% (band %.1f%%)  high-xG blanks %.0f%% of %d" % [
		int(xg["n"]), xg["goals"], xg["xg"], float(xg["gap"]) * 100.0, float(xg["tol"]) * 100.0,
		float(xg["blank_rate"]) * 100.0, int(xg["high_xg"])])


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