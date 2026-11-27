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
	for anchor in CensusLib.ANCHORS.keys():
		var got: Array = pooled.get(anchor, [])
		assert_eq(got.size(), expected_n,
			"%s pooled %d matches across shards; the fixed grid is %d" % [anchor, got.size(), expected_n])
		if got.size() != expected_n:

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
