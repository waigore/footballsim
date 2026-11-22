extends GdToolsTest

## Finishing calibration: an on-target shot converts with probability
## FINISH_EFFICIENCY · xG, and a converted shot cannot be vetoed at the line. These are the engine
## side of the Poisson agreement, tested without running a full match.

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

func test_conversion_probability_tracks_expected_goals() -> void:
	var e := _eng(11)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-9.0, 0.0)
	_clear_box(e)
	var planned := 0
	var xg_sum := 0.0
	var n := 400
	for i in range(n):
		e.rng.seed = 5000 + i
		var xg: float = e.expected_goals(p.pos, 0.0, 0)
		xg_sum += xg
		e.shoot_ball(p, 0.0, 0.5, 1.0)
		if e.ball.planned_goal:
			planned += 1
	var observed := float(planned) / float(n)
	var chance: float = xg_sum / float(n) * e.FINISH_EFFICIENCY
	assert_almost_eq(observed, chance, 0.05, "conversion %.3f does not track calibrated xG %.3f" % [observed, chance])
	assert_gt(chance, 0.06, "fixture is not a real chance")

func test_low_quality_chance_converts_rarely() -> void:
	var e := _eng(12)
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
	var e := _eng(13)
	e.teams[0]["dir"] = 1
	e.teams[1]["dir"] = -1
	var gk = e._gk_of(1)
	gk.pos = Vector2(e.L - 1.0, 34.0)
	e.ball.owner_id = -1
	e.ball.planned_goal = true
	e.ball.shot_team = 0
	e.ball.pos = Vector2(e.L - 0.2, 34.0)
	e.ball.vel = Vector2(40.0, 0.0)
	e.ball.z = 0.4
	e.ball.vz = 0.0
	e.tick()
	assert_eq(int(e.score[0]), 1, "a converted shot was still saved on the line")

func test_unconverted_shot_is_stopped_at_the_line() -> void:
	var e := _eng(14)
	e.teams[0]["dir"] = 1
	e.teams[1]["dir"] = -1
	var gk = e._gk_of(1)
	gk.pos = Vector2(e.L - 1.0, 34.0)
	e.ball.owner_id = -1
	e.ball.planned_goal = false
	e.ball.shot_team = 0
	e.ball.pos = Vector2(e.L - 0.2, 34.0)
	e.ball.vel = Vector2(40.0, 0.0)
	e.ball.z = 0.4
	e.ball.vz = 0.0
	var goals := 0
	for i in range(20):
		e.ball.pos = Vector2(e.L - 0.2, 34.0)
		e.ball.vel = Vector2(40.0, 0.0)
		e.ball.owner_id = -1
		e.ball.shot_team = 0
		e.ball.planned_goal = false
		e.phase = "play"
		e.rng.seed = 700 + i
		var before: int = int(e.score[0])
		e.tick()
		if int(e.score[0]) > before:
			goals += 1
	assert_lte(goals, 4, "the goal-line save let too many unconverted shots through")

func test_a_new_touch_clears_the_planned_flag() -> void:
	var e := _eng(15)
	var p = _striker(e)
	e.ball.planned_goal = true
	e._claim_ball(p)
	assert_false(e.ball.planned_goal, "a claimed ball kept the planned-goal flag")
	e.ball.planned_goal = true
	e.pass_ball(p, p.pos + Vector2(8.0, 0.0))
	assert_false(e.ball.planned_goal, "a pass kept the planned-goal flag")

func test_shot_records_expected_goals() -> void:
	var e := _eng(16)
	var p = _striker(e)
	var goal: Vector2 = e.target_goal_pos(0)
	p.pos = goal + Vector2(-10.0, 0.0)
	_clear_box(e)
	e.shoot_ball(p, 0.0, 0.5, 1.0)
	assert_eq(int(e.stats[0]["shots"]), 1, "the shot was not counted")
	assert_gt(float(e.stats[0]["xg"]), 0.0, "no xG was accumulated")
	assert_eq(int(e.stats[0]["on_target"]), 1, "a corner-placed shot should be on target")
