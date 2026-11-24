extends GdToolsTest

## Census statistics: the reducers the tier-2 Poisson-agreement suites assert
## on, and the sampling-aware tolerance that keeps a 10% agreement target from
## being read as a 10% pass/fail band at census n (the relative sd of S² is
## ~27% at n = 32, so a literal band would fail a correct engine nearly always).

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
	# sd(S²) = sqrt([3λ² + λ − λ²(n−3)/(n−1)] / n) for Poisson(λ) draws.
	var lam := 1.58
	var n := 32
	var expected := sqrt((3.0 * lam * lam + lam - lam * lam * 29.0 / 31.0) / 32.0)
	assert_almost_eq(CensusLib.variance_sampling_sd(lam, n), expected, 0.0001,
		"the Poisson variance-of-variance moment is wrong")
	assert_eq(CensusLib.variance_sampling_sd(0.0, n), 0.0, "zero rate has no noise")
	assert_eq(CensusLib.variance_sampling_sd(lam, 1), 0.0, "one match has no variance estimate")

func test_tolerance_widens_by_the_sampling_allowance() -> void:
	# The gate must never be tighter than the calibration target itself.
	assert_gt(CensusLib.variance_tolerance(1.58, 32), CensusLib.VAR_TARGET,
		"tolerance did not include the sampling allowance")
	# At census n the relative sd of S² is ~29% for λ = 1.58, so the band lands
	# near 10% + 1.96·29% ≈ 67%.
	var band := CensusLib.variance_tolerance(1.58, 32)
	assert_between(band, 0.64, 0.70, "n=32 band is not the 95% Poisson allowance")
	# A stronger anchor (λ = 3.67) is relatively less noisy at the same n.
	assert_lt(CensusLib.variance_tolerance(3.67, 32), band,
		"a higher rate should carry a tighter relative band")

func test_tolerance_shrinks_towards_the_target_with_n() -> void:
	var small := CensusLib.variance_tolerance(3.67, 32)
	var bigger := CensusLib.variance_tolerance(3.67, 400)
	assert_lt(bigger, small, "more matches must tighten the band")
	assert_lt(bigger, 0.30, "n=400 should already resolve a 25% band")
	assert_gt(bigger, CensusLib.VAR_TARGET, "the band must never fall below the target")

func test_engine_grid_gaps_are_inside_the_band() -> void:
	# Regression on the shipped grid reading (PR #53 evidence, unchanged engine):
	# home/away dispersion gaps per anchor as relative fractions of λ.
	var gaps := {
		"mci_bur": [0.38, 0.06],
		"mci_mci": [0.61, 0.48],
	}
	var lambdas := {"mci_bur": [3.67, 0.58], "mci_mci": [1.58, 1.38]}
	for key in gaps.keys():
		var lams: Array = lambdas[key]
		for side in range(2):
			var band := CensusLib.variance_tolerance(float(lams[side]), 32)
			assert_lte(float(gaps[key][side]), band,
				"%s side %d gap sits outside the sampling band" % [key, side])
