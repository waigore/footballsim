extends GdToolsTest


var RESULTS_DIR := TestScratch.dir("census_test_results")

func before_each() -> void:
	_clean_results()

func after_each() -> void:
	_clean_results()

func _clean_results() -> void:
	var base: String = ProjectSettings.globalize_path(RESULTS_DIR)
	if DirAccess.dir_exists_absolute(base):
		var folder := DirAccess.open(base)
		if folder != null:
			for name in folder.get_files():
				DirAccess.remove_absolute(base.path_join(name))
		DirAccess.remove_absolute(base)

func test_sample_variance_and_mean_are_unbiased() -> void:
	var xs: Array = [1, 2, 3, 4]
	assert_almost_eq(CensusLib.mean(xs), 2.5, 0.0001, "mean drifted")
	assert_almost_eq(CensusLib.sample_variance(xs), 5.0 / 3.0, 0.0001, "n−1 variance drifted")
	assert_eq(CensusLib.sample_variance([7]), 0.0, "a single sample has no variance")
	assert_eq(CensusLib.mean([]), 0.0, "empty mean should be zero")

func test_relative_gap_is_symmetric() -> void:
	assert_almost_eq(CensusLib.rel_gap(1.1, 1.0), 0.1, 0.0001, "over-shoot gap wrong")
	assert_almost_eq(CensusLib.rel_gap(0.9, 1.0), 0.1, 0.0001, "under-shoot gap wrong")

func test_sampling_sd_matches_the_poisson_moment() -> void:

	var lam := 1.58
	var n := 32
	var expected := sqrt((3.0 * lam * lam + lam - lam * lam * 29.0 / 31.0) / 32.0)
	assert_almost_eq(CensusLib.variance_sampling_sd(lam, n), expected, 0.0001,
		"the Poisson variance-of-variance moment is wrong")
	assert_eq(CensusLib.variance_sampling_sd(0.0, n), 0.0, "zero rate has no noise")
	assert_eq(CensusLib.variance_sampling_sd(lam, 1), 0.0, "one match has no variance estimate")

func test_tolerance_widens_by_the_sampling_allowance() -> void:

	assert_gt(CensusLib.variance_tolerance(1.58, 32), CensusLib.VAR_TARGET,
		"tolerance did not include the sampling allowance")


	var band := CensusLib.variance_tolerance(1.58, 32)
	assert_between(band, 0.64, 0.70, "n=32 band is not the 95% Poisson allowance")

	assert_lt(CensusLib.variance_tolerance(3.67, 32), band,
		"a higher rate should carry a tighter relative band")

func test_tolerance_shrinks_towards_the_target_with_n() -> void:
	var small := CensusLib.variance_tolerance(3.67, 32)
	var bigger := CensusLib.variance_tolerance(3.67, 400)
	assert_lt(bigger, small, "more matches must tighten the band")
	assert_lt(bigger, 0.30, "n=400 should already resolve a 25% band")
	assert_gt(bigger, CensusLib.VAR_TARGET, "the band must never fall below the target")

func test_shards_partition_the_fixed_grid() -> void:
	var n := CensusLib.GRID_N
	var shards := CensusLib.GRID_SHARDS
	var seen := {}
	for shard in range(shards):
		var idxs := CensusLib.shard_indices(n, shard, shards)
		assert_eq(idxs.size(), n / shards, "shard %d does not carry a full slice" % shard)
		for i in idxs:
			assert_between(int(i), 0, n - 1, "shard index outside the grid")
			assert_false(seen.has(i), "grid index %d is in two shards" % i)
			seen[i] = true
	assert_eq(seen.size(), n, "the shards do not cover the whole grid")

	assert_eq(CensusLib.shard_indices(n, 0, shards)[1], 4, "shard indices are not interleaved")

	assert_eq(CensusLib.shard_indices(n, 0, 1).size(), n, "one shard must hold the grid")

func test_seed_grid_is_fixed_and_strided() -> void:
	assert_eq(CensusLib.seed_for(0), CensusLib.SEED0, "the grid must start at SEED0")
	assert_eq(CensusLib.seed_for(1) - CensusLib.seed_for(0), CensusLib.STRIDE,
		"the grid must step by STRIDE")
	assert_eq(CensusLib.seed_for(31), 7000 + 31 * 13, "the grid moved")

func test_rows_round_trip_and_pool_dedupes() -> void:
	var rows: Array = [
		{"anchor": "mci_mci", "seed": 7000, "home_goals": 2, "away_goals": 1, "ms": 900,
			"xg_home": 1.7, "xg_away": 1.4, "shots_home": 12, "shots_away": 9},
		{"anchor": "mci_mci", "seed": 7013, "home_goals": 0, "away_goals": 3, "ms": 1100,
			"xg_home": 1.2, "xg_away": 2.1, "shots_home": 8, "shots_away": 14},
	]
	var path := CensusLib.write_rows(RESULTS_DIR, "mci_mci", 2, rows)
	assert_false(path.is_empty(), "rows were not written")
	var back := CensusLib.read_rows(RESULTS_DIR)
	assert_eq(back.size(), 2, "rows did not round-trip through JSONL")
	assert_eq(int(back[0]["seed"]), 7000, "the seed did not survive the round trip")

	CensusLib.write_rows(RESULTS_DIR, "mci_mci", 2, rows)
	var pooled := CensusLib.pool_by_anchor(CensusLib.read_rows(RESULTS_DIR))
	assert_eq(pooled["mci_mci"].size(), 2, "pooling double-counted a re-run shard")
	assert_false(pooled.has("mci_ips"), "pooling invented an anchor")

func test_summarise_reports_the_gate_numbers() -> void:
	var rows: Array = []
	for i in range(4):
		rows.append({"anchor": "mci_ips", "seed": 7000 + i * 13, "home_goals": 3 + i % 2,
			"away_goals": 1, "ms": 500 + i * 100, "xg_home": 2.4, "xg_away": 0.7,
			"shots_home": 15, "shots_away": 6})
	var s := CensusLib.summarise("mci_ips", rows)
	assert_eq(int(s["n"]), 4, "summarise lost matches")
	assert_almost_eq(s["mean_home"], 3.5, 0.0001, "home mean drifted")
	assert_almost_eq(s["var_home"], 1.0 / 3.0, 0.0001, "home variance drifted")
	assert_eq(int(s["slowest_ms"]), 800, "the timer gate read the wrong match")
	assert_almost_eq(s["tol_home"], CensusLib.variance_tolerance(s["lambda_home"], 4), 0.0001,
		"the band was not sized from the pooled n")
	assert_almost_eq(s["xg_gap_home"], 1.1 / 2.4, 0.0001, "the goals↔xG gap read the wrong side")
	assert_almost_eq(s["xg_gap_away"], 0.3 / 0.7, 0.0001, "the goals↔xG gap read the wrong side")
	assert_gt(s["xg_tol_home"], CensusLib.GOAL_TARGET, "the xG band dropped its sampling allowance")
	var line := CensusLib.summary_line(s)
	assert_true(line.begins_with("CENSUS mci_ips n=4"), "the summary line is not readable")
	assert_true(line.contains("xG 2.40-0.70"), "the summary line lost the xG column")

func test_goals_tolerance_carries_the_target_and_the_allowance() -> void:
	assert_almost_eq(CensusLib.goals_tolerance(2.75, 0.0, 32), CensusLib.GOAL_TARGET, 0.0001,
		"a noiseless cell must read the 10% target")
	var noisy := CensusLib.goals_tolerance(2.75, 1.6, 32)
	var tighter := CensusLib.goals_tolerance(2.75, 1.6, 128)
	assert_gt(noisy, CensusLib.GOAL_TARGET, "the band dropped the sampling allowance")
	assert_lt(tighter, noisy, "more matches must tighten the xG band")
	assert_eq(CensusLib.goals_tolerance(0.0, 1.0, 32), CensusLib.GOAL_TARGET, "a zero xG cell drifted")
	assert_eq(CensusLib.goals_tolerance(2.0, 1.0, 1), 1.0, "one match cannot size a band")

func test_pooled_xg_reads_every_side_and_the_blank_rate() -> void:
	var by_anchor := {
		"mci_ips": [
			{"home_goals": 3, "away_goals": 0, "xg_home": 2.8, "xg_away": 0.4},
			{"home_goals": 2, "away_goals": 1, "xg_home": 2.6, "xg_away": 0.5},
		],
		"mci_mci": [
			{"home_goals": 0, "away_goals": 2, "xg_home": 2.2, "xg_away": 1.2},
			{"home_goals": 1, "away_goals": 1, "xg_home": 1.4, "xg_away": 1.1},
		],
	}
	var xg := CensusLib.xg_pooled(by_anchor)
	assert_eq(int(xg["n"]), 8, "pooling missed a side")
	assert_almost_eq(xg["goals"], 1.25, 0.0001, "pooled goals drifted")
	assert_almost_eq(xg["xg"], 1.525, 0.0001, "pooled xG drifted")
	assert_almost_eq(xg["gap"], 0.275 / 1.525, 0.0001, "pooled gap drifted")
	assert_eq(int(xg["high_xg"]), 3, "the blank read counted the wrong sides")
	assert_almost_eq(xg["blank_rate"], 1.0 / 3.0, 0.0001, "one blank in three high-xG sides")
	assert_gt(xg["tol"], CensusLib.GOAL_TARGET, "the pooled band dropped its allowance")
