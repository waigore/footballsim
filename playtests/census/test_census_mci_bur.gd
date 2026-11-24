extends GdToolsTest

## Tier-2 census: physics engine vs Poisson model on the MCI v BUR anchor.
## Parent: #31 (physics↔Poisson variance agreement). Runs N seeded full
## physics matches on a fixed grid and hard-gates two things:
##
##   1. Goal variance: |sample_var − λ| / λ ≤ 10% for home and away,
##      Poisson being the source of truth. Means and xG are logged for
##      diagnosis but deliberately not gated.
##   2. Sim cost: every full match must finish within the wall-clock budget.
##
## The grid is fixed (SEED0 + i * STRIDE) so the gate is deterministic: a
## failure means the engine's agreement or per-match cost moved, not CI noise.
## Sampling uncertainty of the variance statistic at this n is documented on
## the wiki poisson-model page next to the latest census numbers.
## Tier-2 only: never selected by PR tier-1 (impact map keeps census drives on
## the fast poisson suite).

const HOME := "MCI"
const AWAY := "BUR"

const N := 32         # matches on the fixed grid
const SEED0 := 7000
const STRIDE := 13
const VAR_TOLERANCE := 0.10
# Wall-clock budget for one full headless physics match. A 60 Hz tick in
# GDScript bottoms out around 25-30 s locally (CI runners slower), so the
# budget sits at 60 s: it fails gross sim-cost regressions while a native
# (GDExtension) hot loop stays a follow-up.
const MATCH_BUDGET_MS := 60_000

func test_census_variance_and_match_budget() -> void:
	var model := PoissonModel.new(SEED0, HOME, AWAY)
	var goals_h: Array = []
	var goals_a: Array = []
	var xg_h := 0.0
	var xg_a := 0.0
	var slowest_ms := 0
	for i in range(N):
		var r := CensusLib.run_match(HOME, AWAY, SEED0 + i * STRIDE)
		goals_h.append(r["home_goals"])
		goals_a.append(r["away_goals"])
		xg_h += float(r["xg_home"])
		xg_a += float(r["xg_away"])
		slowest_ms = maxi(slowest_ms, int(r["ms"]))
		# Per-match sim-cost budget: a full headless match may not exceed it.
		assert_lte(int(r["ms"]), MATCH_BUDGET_MS,
			"full match %d took %d ms (budget %d ms)" % [r["seed"], r["ms"], MATCH_BUDGET_MS])
	var var_h := CensusLib.sample_variance(goals_h)
	var var_a := CensusLib.sample_variance(goals_a)
	var gap_h := CensusLib.rel_gap(var_h, model.lambda_home)
	var gap_a := CensusLib.rel_gap(var_a, model.lambda_away)
	print("CENSUS %s v %s n=%d seed0=%d stride=%d  goals %.2f-%.2f (λ %.2f-%.2f)  var %.2f-%.2f  xG %.2f-%.2f  slowest %d ms" % [
		HOME, AWAY, N, SEED0, STRIDE,
		CensusLib.mean(goals_h), CensusLib.mean(goals_a),
		model.lambda_home, model.lambda_away, var_h, var_a,
		xg_h / N, xg_a / N, slowest_ms])
	assert_lte(gap_h, VAR_TOLERANCE,
		"home goal variance %.2f is %.0f%% off λ %.2f (gate %.0f%%)" % [
			var_h, gap_h * 100.0, model.lambda_home, VAR_TOLERANCE * 100.0])
	assert_lte(gap_a, VAR_TOLERANCE,
		"away goal variance %.2f is %.0f%% off λ %.2f (gate %.0f%%)" % [
			var_a, gap_a * 100.0, model.lambda_away, VAR_TOLERANCE * 100.0])
