class_name CensusLib
extends RefCounted

## Shared helpers for the tier-2 Poisson-agreement census suites. Not a test
## suite: it only runs full matches and reduces the sample statistics the
## suites assert on. Kept next to the suites so the census is one unit.

## Agreement target: the calibration goal is a relative gap of ≤ 10% between
## sample variance and the model's λ. Big-n manual censuses are the evidence
## for that goal; the suite grid alone cannot resolve it (see below).
const VAR_TARGET := 0.10

## Wall-clock budget for one full headless physics match (a 60 Hz GDScript tick
## bottoms out near 30 s; tighten with a native hot loop later).
const MATCH_BUDGET_MS := 60_000

## Two-sided 95% coverage factor for the sampling band around λ.
const VAR_Z := 1.96

## Play one full physics match headless and return its outcome and wall clock.
static func run_match(home: String, away: String, seed_in: int) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var eng := MatchEngine.new(seed_in, home, away)
	var guard := 0
	while eng.phase != "full_time" and guard < 60 * 60 * 400:
		if eng.phase == "half_time":
			eng.begin_second_half()
		eng.tick()
		guard += 1
	var ms := Time.get_ticks_msec() - t0
	return {
		"seed": seed_in, "home_goals": int(eng.score[0]), "away_goals": int(eng.score[1]),
		"ms": ms, "xg_home": float(eng.stats[0]["xg"]), "xg_away": float(eng.stats[1]["xg"]),
		"shots_home": int(eng.stats[0]["shots"]), "shots_away": int(eng.stats[1]["shots"]),
	}

## Unbiased sample variance (n-1 denominator), same as the manual drive in
## tests/check_poisson_agreement.gd.
static func sample_variance(xs: Array) -> float:
	if xs.size() < 2:
		return 0.0
	var total := 0.0
	for x in xs:
		total += float(x)
	var m: float = total / xs.size()
	var acc := 0.0
	for x in xs:
		acc += (float(x) - m) * (float(x) - m)
	return acc / (xs.size() - 1)

static func mean(xs: Array) -> float:
	if xs.is_empty():
		return 0.0
	var total := 0.0
	for x in xs:
		total += float(x)
	return total / xs.size()

## Relative distance between a sample statistic and the model value.
static func rel_gap(sample: float, model: float) -> float:
	return absf(sample - model) / model

## Standard deviation of the unbiased sample variance S² when the counts are
## Poisson(lam) draws, i.e. the noise the census inherits from its own n.
##
## Var(S²) = [μ4 − σ⁴·(n−3)/(n−1)] / n with σ² = λ and μ4 = 3λ² + λ.
static func variance_sampling_sd(lam: float, n: int) -> float:
	if n < 2 or lam <= 0.0:
		return 0.0
	var var_s2 := (3.0 * lam * lam + lam - lam * lam * float(n - 3) / float(n - 1)) / float(n)
	return sqrt(maxf(var_s2, 0.0))

## Relative half-width the census may tolerate: the 10% agreement target plus
## the two-sided 95% sampling allowance at this n and λ.
##
## The bare 10% tolerance sits *below* the census's own sampling noise (the
## relative sd of S² is ~27% at n = 32), so a literal 10% gate would fail an
## honestly calibrated engine almost every run — and could only be turned green
## by tuning to the fixed seeds. Widening by the sampling band keeps the 10%
## goal as the calibration target (proved by big-n manual censuses) while the
## fixed grid stays a reproducible drift tripwire: it fails when the engine's
## dispersion moves by more than n can explain.
static func variance_tolerance(lam: float, n: int) -> float:
	return VAR_TARGET + VAR_Z * variance_sampling_sd(lam, n) / maxf(lam, 0.001)
