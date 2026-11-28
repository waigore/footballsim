extends GdToolsTest


func _eng(seed: int = 1) -> MatchEngine:
	var e := MatchEngine.new(seed)
	e.phase = "play"
	e.restart = {}
	return e

func _striker(e: MatchEngine):
	for p in e.players:
		if p.team == 0 and p.role == "ST":
			return p
	return null

func _clear_box(e: MatchEngine) -> void:
	for q in e.players:
		if q.team == 1 and not q.is_gk:
			q.pos = Vector2(e.L * 0.5, 4.0)
			q.vel = Vector2.ZERO

func _park_keeper(e: MatchEngine, at: Vector2) -> void:
	var gk = e._gk_of(1)
	gk.pos = at
	gk.cooldown = 0.0

func test_the_split_prices_every_shot_at_its_displayed_xg() -> void:
	var e := _eng(10)
	for xg in [0.006, 0.02, 0.05, 0.11, 0.3, 0.6, 0.86]:
		for save in [0.18, 0.5, 0.8, 0.95, 0.985]:
			var split: Array = e._shot_split(xg, save)
			var planned: float = float(split[0])
			var residual: float = float(split[1])
			var priced: float = planned + residual * (1.0 - save)
			assert_almost_eq(priced, xg, 0.0001,
				"chance %.3f against a %.2f save priced %.3f" % [xg, save, priced])
			assert_between(planned, 0.0, 1.0, "planned share left the unit interval")
			assert_between(residual, 0.0, 1.0, "residual share left the unit interval")
			assert_lte(planned + residual, 1.0, "the shot shares added up past one")

func test_the_split_keeps_unconverted_shots_on_target() -> void:
	var e := _eng(11)
	var split: Array = e._shot_split(0.12, 0.9)
	assert_between(float(split[1]), 0.2, 0.45,
		"a %.2f xG chance left %.2f of its shots as live on-target threats" % [0.12, split[1]])
	assert_between(float(split[0]) + float(split[1]), 0.25, 0.55,
		"the on-target share %.2f is outside the census family" % (float(split[0]) + float(split[1])))

func test_one_expected_goal_is_recorded_per_shot() -> void:
	var e := _eng(12)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-10.0, 0.0)
	_clear_box(e)
	var xg_sum := 0.0
	var on_target := 0
	var n := 200
	for i in range(n):
		e.rng.seed = 5000 + i
		var before: float = float(e.stats[0]["xg"])
		var shots: int = int(e.stats[0]["shots"])
		xg_sum += e.expected_goals(p.pos, 0.0, 0)
		e.shoot_ball(p, 0.0, 0.5, 1.0)
		assert_eq(int(e.stats[0]["shots"]), shots + 1, "the shot was counted twice")
		var added: float = float(e.stats[0]["xg"]) - before
		assert_almost_eq(added, e.expected_goals(p.pos, 0.0, 0), 0.0001,
			"the shot recorded %.3f xG against a %.3f chance" % [added, e.expected_goals(p.pos, 0.0, 0)])
		if int(e.stats[0]["on_target"]) > on_target:
			on_target += 1
	assert_between(float(on_target) / float(n), 0.20, 0.60,
		"%.0f%% of a 10 m chance was on target" % (100.0 * float(on_target) / float(n)))
	assert_gt(xg_sum / float(n), 0.03, "fixture is not a real chance")

func test_low_quality_chance_converts_rarely() -> void:
	var e := _eng(13)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-30.0, 14.0)
	_clear_box(e)
	var planned := 0
	var n := 300
	var xg_sum := 0.0
	for i in range(n):
		e.rng.seed = 9000 + i
		xg_sum += e.expected_goals(p.pos, 0.0, 0)
		e.shoot_ball(p, 0.0, 0.5, 1.0)
		if e.ball.planned_goal:
			planned += 1
	assert_lt(float(planned) / float(n), 0.10, "a 33m shot converted far too often")
	assert_gt(xg_sum / float(n), 0.0, "xG was not recorded for a long shot")

func test_converted_shot_beats_the_line_save() -> void:
	var e := _eng(14)
	e.teams[0]["dir"] = 1
	e.teams[1]["dir"] = -1
	_park_keeper(e, Vector2(e.L - 1.0, 34.0))
	e.ball.owner_id = -1
	e.ball.planned_goal = true
	e.ball.shot_team = 0
	e.ball.pos = Vector2(e.L - 0.2, 34.0)
	e.ball.vel = Vector2(40.0, 0.0)
	e.ball.z = 0.4
	e.ball.vz = 0.0
	e.tick()
	assert_eq(int(e.score[0]), 1, "a converted shot was still saved on the line")

func test_an_unconverted_shot_can_still_beat_the_keeper() -> void:
	var e := _eng(20)
	e.teams[0]["dir"] = 1
	e.teams[1]["dir"] = -1
	_park_keeper(e, Vector2(e.L - 1.0, 24.0))
	var goals := 0
	for i in range(40):
		e.score[0] = 0
		e.phase = "play"
		e.ball.owner_id = -1
		e.ball.planned_goal = false
		e.ball.shot_team = 0
		e.ball.shot_time = e.clock
		e.ball.pos = Vector2(e.L, 37.0)
		e.ball.vel = Vector2(40.0, 0.0)
		e.ball.z = 0.4
		e.ball.vz = 0.0
		e.rng.seed = 1700 + i
		e._check_rules()
		if int(e.score[0]) > 0:
			goals += 1
	assert_eq(goals, 40, "an on-target shot beat by an out-of-position keeper was still saved")

func test_a_keeper_in_position_saves_a_live_on_target_shot() -> void:
	var e := _eng(21)
	e.teams[0]["dir"] = 1
	e.teams[1]["dir"] = -1
	_park_keeper(e, Vector2(e.L - 1.0, 37.0))
	var goals := 0
	var saves := 0
	for i in range(40):
		e.score[0] = 0
		e.phase = "play"
		e.ball.owner_id = -1
		e.ball.planned_goal = false
		e.ball.shot_team = 0
		e.ball.shot_time = e.clock
		e.ball.pos = Vector2(e.L, 37.0)
		e.ball.vel = Vector2(40.0, 0.0)
		e.ball.z = 0.4
		e.ball.vz = 0.0
		e.rng.seed = 1900 + i
		e._check_rules()
		if int(e.score[0]) > 0:
			goals += 1
		if e.phase == "play":
			saves += 1
	assert_gt(saves, 30, "a keeper on the shot line let too many live shots through")
	assert_lt(goals, 10, "the goal line ignored a keeper standing on the shot")

func test_unconverted_shots_are_not_all_steered_at_the_keeper() -> void:
	var e := _eng(15)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-12.0, 4.0)
	_clear_box(e)
	_park_keeper(e, goal + Vector2(-0.6, 0.0))
	var spread := 0.0
	var live := 0
	var n := 300
	for i in range(n):
		e.rng.seed = 3000 + i
		e.shoot_ball(p, 2.4, 0.6, 1.0)
		if e.ball.planned_goal:
			continue
		live += 1
		var dir: Vector2 = e.ball.vel.normalized()
		spread += absf((goal.x - p.pos.x) * dir.y / maxf(absf(dir.x), 0.01))
	assert_gt(live, n / 2, "almost every shot was a planned goal")
	assert_gt(spread / float(maxi(live, 1)), 1.5,
		"unconverted shots were steered back at the keeper")

func test_a_new_touch_clears_the_planned_flag() -> void:
	var e := _eng(16)
	var p = _striker(e)
	e.ball.planned_goal = true
	e._claim_ball(p)
	assert_false(e.ball.planned_goal, "a claimed ball kept the planned-goal flag")
	e.ball.planned_goal = true
	e.pass_ball(p, p.pos + Vector2(8.0, 0.0))
	assert_false(e.ball.planned_goal, "a pass kept the planned-goal flag")

func test_a_penalty_counts_one_shot_and_one_xg() -> void:
	var e := _eng(17)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-11.0, 0.0)
	e._start_restart("penalty", 0, p.pos)
	var shots: int = int(e.stats[0]["shots"])
	var xg: float = float(e.stats[0]["xg"])
	var on_target: int = int(e.stats[0]["on_target"])
	e._execute_restart()
	assert_eq(int(e.stats[0]["shots"]), shots + 1, "the penalty was counted as two shots")
	assert_gte(int(e.stats[0]["on_target"]), on_target, "the penalty never counted as on target")
	var taker = e.by_id.get(e.ball.last_touch_id, null)
	assert_true(taker != null, "the penalty left no taker on the ball")
	var added: float = float(e.stats[0]["xg"]) - xg
	assert_almost_eq(added, e.penalty_conversion(taker), 0.0001,
		"the penalty carried %.3f xG against a %.3f conversion" % [added, e.penalty_conversion(taker)])

func test_a_penalty_nearly_always_scores() -> void:
	var e := _eng(18)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-11.0, 0.0)
	var scored := 0
	var n := 200
	for i in range(n):
		e.rng.seed = 6100 + i
		var split: Array = e._shot_split(e.penalty_conversion(p), 0.9)
		if e.rng.randf() < float(split[0]) + float(split[1]) * 0.1:
			scored += 1
	assert_gt(float(scored) / float(n), 0.6, "a penalty scored less than six times in ten")

func test_shot_records_expected_goals() -> void:
	var e := _eng(19)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-10.0, 0.0)
	_clear_box(e)
	e.shoot_ball(p, 0.0, 0.5, 1.0)
	assert_eq(int(e.stats[0]["shots"]), 1, "the shot was not counted")
	assert_gt(float(e.stats[0]["xg"]), 0.0, "no xG was accumulated")
	assert_lte(int(e.stats[0]["on_target"]), 1, "one shot was counted on target twice")


func test_chance_quality_tracks_the_defence_faced() -> void:


	var weak := MatchEngine.new(1, "ENG-MCI1", "ENG-IPS1")
	var strong := MatchEngine.new(1, "ENG-MCI1", "ENG-NEW1")
	var spot: Vector2 = weak.target_goal_pos(0) + Vector2(-14.0, 5.0)
	var vs_weak: float = weak.expected_goals(spot, 0.0, 0) / _open_home("ENG-MCI1", "ENG-IPS1")
	var vs_strong: float = strong.expected_goals(spot, 0.0, 0) / _open_home("ENG-MCI1", "ENG-NEW1")
	assert_gt(vs_weak, vs_strong, "a shot against a weak defence was not worth more")
	var ex_weak := PoissonModel.defence_exponents("ENG-MCI1", "ENG-IPS1")
	var ex_strong := PoissonModel.defence_exponents("ENG-MCI1", "ENG-NEW1")
	var expected: float = exp(MatchEngine.XG_CONTEST_ELASTICITY * (ex_weak.x - ex_strong.x))
	assert_almost_eq(vs_weak / vs_strong, expected, 0.001,
		"the contest gap does not read the model's defensive exponent")


func _open_total(home: String, away: String) -> float:
	var ex := PoissonModel.side_exponents(home, away)
	return (PoissonModel.HOME_XG * exp(ex.x) + PoissonModel.AWAY_XG * exp(ex.y)) / (PoissonModel.HOME_XG + PoissonModel.AWAY_XG)


func _open_home(home: String, away: String) -> float:
	var ex := PoissonModel.side_exponents(home, away)
	var total := _open_total(home, away)
	return minf(total, sqrt(total * exp(ex.x)))


func _open_away(home: String, away: String) -> float:
	var ex := PoissonModel.side_exponents(home, away)
	var total := _open_total(home, away)
	return minf(total, sqrt(total * exp(ex.y)))

func test_chance_quality_tracks_how_open_the_fixture_is() -> void:


	var even := MatchEngine.new(1, "ENG-MCI1", "ENG-MCI1")
	var gap := MatchEngine.new(1, "ENG-MCI1", "ENG-IPS1")
	var spot: Vector2 = even.target_goal_pos(0) + Vector2(-14.0, 5.0)
	var in_even: float = even.expected_goals(spot, 0.0, 0)
	var in_gap: float = gap.expected_goals(spot, 0.0, 0)
	assert_gt(in_gap, in_even, "the open fixture did not price the same chance higher")
	var eg := PoissonModel.exponent_terms("ENG-MCI1", "ENG-IPS1")
	var ee := PoissonModel.exponent_terms("ENG-MCI1", "ENG-MCI1")
	var contest: float = exp(MatchEngine.XG_CONTEST_ELASTICITY * ((eg["attack"].x + eg["defence"].x) - (ee["attack"].x + ee["defence"].x)))
	var expected: float = contest * _open_home("ENG-MCI1", "ENG-IPS1") / _open_home("ENG-MCI1", "ENG-MCI1")
	assert_almost_eq(in_gap / in_even, expected, 0.001,
		"the level gap between the anchors is not the model's openness")

func test_contest_factor_is_bounded_and_reads_the_ratings() -> void:


	var strong_home := MatchEngine.new(1, "ENG-MCI1", "ENG-IPS1")
	var even := MatchEngine.new(1, "ENG-MCI1", "ENG-MCI1")
	var strong_away := MatchEngine.new(1, "ENG-IPS1", "ENG-MCI1")
	var gap_home: float = float(strong_home.xg_form[0]) / _open_home("ENG-MCI1", "ENG-IPS1")
	var evening: float = float(even.xg_form[0]) / _open_home("ENG-MCI1", "ENG-MCI1")
	var gap_away: float = float(strong_away.xg_form[0]) / _open_home("ENG-IPS1", "ENG-MCI1")
	assert_gt(gap_home, evening, "a top side against a weak defence did not get the better contest")
	assert_lt(gap_away, evening, "a weak side at home was given the same contest as an even fixture")
	for pair in [["ENG-MCI1", "ENG-IPS1"], ["ENG-MCI1", "ENG-MCI1"], ["ENG-MCI1", "ENG-ARS1"], ["ENG-IPS1", "ENG-MCI1"], ["ENG-IPS1", "ENG-ARS1"]]:
		var e := MatchEngine.new(1, pair[0], pair[1])
		assert_between(float(e.xg_form[0]), 0.30, 3.00,
			"%s v %s home contest factor is out of family" % [pair[0], pair[1]])
		assert_between(float(e.xg_form[1]), 0.30, 3.00,
			"%s v %s away contest factor is out of family" % [pair[0], pair[1]])

func test_equal_squads_carry_no_pricing_edge() -> void:


	var e := MatchEngine.new(1, "ENG-MCI1", "ENG-MCI1")
	assert_eq(MatchEngine.XG_HOME_EDGE, 0.0, "the finishing multiplier prices the venue again")
	assert_almost_eq(float(e.xg_form[0]) / float(e.xg_form[1]), 1.0, 0.0001,
		"equal squads did not read the same chance quality")
	var goal: Vector2 = e.target_goal_pos(0)
	var xg: float = e.expected_goals(goal + Vector2(-11.0, 0.0), 0.0, 0)
	assert_between(xg, 0.061, 0.071, "a central 11 m chance is outside the calibrated band")

func test_the_canonical_chance_sits_on_the_census_level() -> void:


	var even := MatchEngine.new(1, "ENG-MCI1", "ENG-MCI1")
	var strong := MatchEngine.new(1, "ENG-MCI1", "ENG-IPS1")
	var even_xg: float = even.expected_goals(even.target_goal_pos(0) + Vector2(-12.0, 0.0), 0.0, 0)
	var strong_xg: float = strong.expected_goals(strong.target_goal_pos(0) + Vector2(-12.0, 0.0), 0.0, 0)
	assert_between(even_xg, 0.051, 0.061, "the even fixture's chance left the calibrated level")
	assert_between(strong_xg, 0.085, 0.097, "the rating-gap chance left the calibrated level")

func test_underdog_openness_is_capped_below_the_fixture_total() -> void:


	var gap := MatchEngine.new(1, "ENG-MCI1", "ENG-IPS1")
	var total := _open_total("ENG-MCI1", "ENG-IPS1")
	assert_almost_eq(float(gap.xg_form[0]) / exp(MatchEngine.XG_CONTEST_ELASTICITY * (
		PoissonModel.exponent_terms("ENG-MCI1", "ENG-IPS1")["attack"].x
		+ PoissonModel.exponent_terms("ENG-MCI1", "ENG-IPS1")["defence"].x)), total, 0.001,
		"the favourite still reads the fixture's shared openness")
	assert_lt(_open_away("ENG-MCI1", "ENG-IPS1"), total,
		"the underdog kept the shared openness that overprices thin chances")
	assert_almost_eq(float(gap.xg_form[1]), exp(MatchEngine.XG_CONTEST_ELASTICITY * (
		PoissonModel.exponent_terms("ENG-MCI1", "ENG-IPS1")["attack"].y
		+ PoissonModel.exponent_terms("ENG-MCI1", "ENG-IPS1")["defence"].y)) * _open_away("ENG-MCI1", "ENG-IPS1"), 0.001,
		"the underdog's chance quality is not the capped openness")