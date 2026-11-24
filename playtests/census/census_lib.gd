class_name CensusLib
extends RefCounted

## Shared helpers for the tier-2 Poisson-agreement census suites. Not a test
## suite: it only runs full matches and reduces the sample statistics the
## suites assert on. Kept next to the suites so the census is one unit.

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
