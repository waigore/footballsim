extends GdToolsTest

## Poisson / Dixon-Coles scoreline model: rating-driven λ, a normalised joint
## distribution, the low-score correction, deterministic sampling and the
## weather/modifier knobs.

const HOME := "MCI"
const AWAY := "BUR"

func _model(seed: int = 1, h: String = HOME, a: String = AWAY, weather: String = "clear",
		mods: Dictionary = {}) -> PoissonModel:
	return PoissonModel.new(seed, h, a, weather, mods)

# ----------------------------------------------------------- rating model ---

func test_league_means_cover_every_club() -> void:
	var means := PoissonModel.league_means()
	assert_eq(int(means["clubs"]), TeamData.team_ids().size(), "league means did not cover every club")
	assert_between(float(means["attack"]), 60.0, 95.0, "attack mean outside the rating scale")
	assert_between(float(means["defence"]), 60.0, 95.0, "defence mean outside the rating scale")

func test_strength_reads_roles_not_just_overall() -> void:
	var mci := PoissonModel.team_strength(TeamData.get_team("MCI"))
	var bur := PoissonModel.team_strength(TeamData.get_team("BUR"))
	assert_gt(float(mci["attack"]), float(bur["attack"]), "the stronger attack was not read as such")
	assert_gt(float(mci["defence"]), float(bur["defence"]), "the stronger defence was not read as such")
	assert_gt(float(mci["midfield"]), float(bur["midfield"]), "the stronger midfield was not read as such")
	assert_between(float(mci["midfield"]), float(mci["attack"]) - 12.0, float(mci["attack"]) + 12.0,
		"midfield reading is out of family with the rest of the squad")

func test_equal_sides_get_home_advantage_only() -> void:
	var m := _model(1, "MCI", "MCI")
	assert_gt(m.lambda_home, m.lambda_away, "equal sides had no home advantage")
	assert_almost_eq(m.lambda_home, PoissonModel.HOME_XG, 0.20, "home λ drifted from the league baseline")
	assert_almost_eq(m.lambda_away, PoissonModel.AWAY_XG, 0.20, "away λ drifted from the league baseline")
	assert_between(m.lambda_home + m.lambda_away, 2.40, 3.00, "an even fixture should sit near the league total")

func test_rating_gap_drives_expected_goals() -> void:
	var m := _model()
	assert_gte(m.lambda_home, 2.20, "an 11-point rating edge should clear 2.2 expected goals")
	assert_lte(m.lambda_away, 0.95, "the weaker side kept too much of its expected goals")
	assert_gt(m.lambda_home / m.lambda_away, 2.5, "the rating gap did not translate into a λ ratio")
	# Monotone in the gap: the closer the opponent, the fewer the home goals.
	var vs_ars := _model(1, "MCI", "ARS")
	var vs_mun := _model(1, "MCI", "MUN")
	var vs_bur := _model(1, "MCI", "BUR")
	assert_gt(vs_bur.lambda_home, vs_mun.lambda_home, "λ is not monotone in opponent strength")
	assert_gt(vs_mun.lambda_home, vs_ars.lambda_home, "λ is not monotone in opponent strength")
	assert_lt(vs_bur.lambda_away, vs_mun.lambda_away, "the weaker side was given too many goals")
	assert_lt(vs_mun.lambda_away, vs_ars.lambda_away, "the opponent's λ is not monotone in their rating")

# ------------------------------------------------------------ distribution --

func test_exponent_terms_feed_both_consumers() -> void:
	# λ's exponent is published as its two halves so the physics engine's shot
	# contest can read the defensive half without deriving ratings again.
	var terms := PoissonModel.exponent_terms(HOME, AWAY)
	var attack: Vector2 = terms["attack"]
	var defence: Vector2 = terms["defence"]
	var ex := PoissonModel.side_exponents(HOME, AWAY)
	assert_almost_eq(ex.x, PoissonModel.ATTACK_ELASTICITY * attack.x + PoissonModel.DEFENCE_ELASTICITY * defence.x,
		0.0001, "home exponent is not the sum of its terms")
	assert_almost_eq(ex.y, PoissonModel.ATTACK_ELASTICITY * attack.y + PoissonModel.DEFENCE_ELASTICITY * defence.y,
		0.0001, "away exponent is not the sum of its terms")
	var def_ex := PoissonModel.defence_exponents(HOME, AWAY)
	assert_almost_eq(def_ex.x, defence.x, 0.0001, "defence_exponents disagrees with exponent_terms")
	assert_almost_eq(def_ex.y, defence.y, 0.0001, "defence_exponents disagrees with exponent_terms")
	# Facing BUR's back line is a break; facing ARS's is not.
	assert_gt(def_ex.x, 0.0, "BUR's defence was not read as below the league")
	assert_lt(PoissonModel.defence_exponents(HOME, "ARS").x, 0.0, "ARS's defence was not read as above the league")

func test_distribution_is_normalised() -> void:
	var m := _model()
	var total := 0.0
	for y in range(PoissonModel.MAX_GOALS + 1):
		for x in range(PoissonModel.MAX_GOALS + 1):
			var p := m.joint(x, y)
			assert_gte(p, 0.0, "negative probability at %d-%d" % [x, y])
			total += p
	assert_almost_eq(total, 1.0, 0.0001, "the score grid does not sum to one")
	assert_eq(m.joint(-1, 0), 0.0, "out-of-grid cells should be zero")

func test_dixon_coles_lifts_low_scoring_draws() -> void:
	var m := _model()
	var plain_00 := exp(-m.lambda_home) * exp(-m.lambda_away)
	var plain_11 := exp(-m.lambda_home) * m.lambda_home * exp(-m.lambda_away) * m.lambda_away
	assert_gt(m.joint(0, 0), 0.0, "0-0 vanished")
	# The corrected 0-0 and 1-1 must beat plain Poisson (up to normalisation).
	var ratio_00 := m.joint(0, 0) / plain_00
	var ratio_11 := m.joint(1, 1) / plain_11
	var ratio_10 := m.joint(1, 0) / (plain_11 / m.lambda_away)
	var ratio_01 := m.joint(0, 1) / (plain_11 / m.lambda_home)
	assert_gt(ratio_00, ratio_10, "0-0 was not lifted relative to 1-0")
	assert_gt(ratio_11, ratio_01, "1-1 was not lifted relative to 0-1")
	assert_gt(ratio_11, ratio_10, "1-1 was not lifted relative to 1-0")

func test_outcome_markets_are_consistent() -> void:
	var m := _model()
	var o := m.outcomes()
	assert_almost_eq(float(o["home"]) + float(o["draw"]) + float(o["away"]), 1.0, 0.0005,
		"match-result probabilities do not sum to one")
	assert_almost_eq(float(o["home"]), _market(m, "home"), 0.0005, "home win market disagrees with the grid")
	assert_gte(float(o["over_2_5"]), 0.0, "negative over 2.5")
	assert_lte(float(o["over_2_5"]), 1.0, "over 2.5 above one")
	assert_gte(float(o["btts"]), 0.0, "negative both-teams-to-score")
	var strong: Dictionary = m.outcomes()
	var weak: Dictionary = _model(1, "BUR", "MCI").outcomes()
	assert_gt(float(strong["home"]), float(weak["home"]), "the stronger side was not favoured at home")
	assert_gt(float(weak["away"]), float(weak["home"]), "the stronger side was not favoured away")

func _market(m: PoissonModel, kind: String) -> float:
	var acc := 0.0
	for y in range(PoissonModel.MAX_GOALS + 1):
		for x in range(PoissonModel.MAX_GOALS + 1):
			if kind == "home" and x > y:
				acc += m.joint(x, y)
	return acc

# ---------------------------------------------------------------- sampling --

func test_sampling_matches_the_distribution() -> void:
	var m := _model(4242)
	var n := 8000
	var counts := {}
	for i in range(n):
		var s := m.sample()
		var key := "%d-%d" % [s.x, s.y]
		counts[key] = int(counts.get(key, 0)) + 1
	var worst := 0.0
	var worst_key := ""
	for y in range(0, 5):
		for x in range(0, 5):
			var observed := float(counts.get("%d-%d" % [x, y], 0)) / float(n)
			var err := absf(observed - m.joint(x, y))
			if err > worst:
				worst = err
				worst_key = "%d-%d" % [x, y]
	assert_lt(worst, 0.02, "sampling drifted from the grid at %s (%.3f)" % [worst_key, worst])

func test_sampling_is_deterministic_per_seed() -> void:
	var a := _model(77)
	var b := _model(77)
	for i in range(20):
		var sa := a.sample()
		var sb := b.sample()
		assert_eq(sa, sb, "the same seed produced different scorelines")
	var c := _model(78)
	var differ := false
	for i in range(20):
		if c.sample() != a.sample():
			differ = true
			break
	assert_true(differ, "different seeds produced the same scoreline sequence")

# ------------------------------------------------------------------ knobs ---

func test_weather_reduces_goals() -> void:
	var dry := _model(1)
	var rain := _model(1, HOME, AWAY, "rain")
	var snow := _model(1, HOME, AWAY, "snow")
	assert_lt(rain.lambda_home + rain.lambda_away, dry.lambda_home + dry.lambda_away, "rain did not reduce goals")
	assert_lt(snow.lambda_home + snow.lambda_away, rain.lambda_home + rain.lambda_away, "snow was not worse than rain")

func test_modifiers_apply_per_side_and_in_total() -> void:
	var base := _model(1)
	var tired_home := _model(1, HOME, AWAY, "clear", {"home": 0.8})
	assert_almost_eq(tired_home.lambda_home, base.lambda_home * 0.8, 0.001, "home modifier ignored")
	assert_almost_eq(tired_home.lambda_away, base.lambda_away, 0.001, "home modifier leaked into the away side")
	var cagey := _model(1, HOME, AWAY, "clear", {"total": 0.5})
	assert_almost_eq(cagey.lambda_home, base.lambda_home * 0.5, 0.001, "total modifier ignored")
	assert_almost_eq(cagey.lambda_away, base.lambda_away * 0.5, 0.001, "total modifier ignored")

func test_expected_goals_are_capped() -> void:
	var m := _model(1, "MCI", "BUR", "clear", {"home": 9.0})
	assert_lte(m.lambda_home, 6.5, "λ was not clamped")
	assert_gte(m.lambda_home, 0.05, "λ was not clamped")
