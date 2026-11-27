extends GdToolsTest


const W := 68.0
const GOAL_W := 7.32
const GOAL_H := 2.44

func _eng(seed_in: int = 51) -> MatchEngine:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "play"
	eng.restart = {}
	eng.ball.owner_id = -1
	return eng

func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk:
			return p
	return null

func _park_keepers(eng) -> void:
	for p in eng.players:
		if p.is_gk:
			p.pos = Vector2(52.5, 34.0)
			p.cooldown = 0.0

func _events(eng, kind: String) -> int:
	var n := 0
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			n += 1
	return n


func _shot_at(eng, team: int, y: float, z: float, past: float = 0.10):
	var goal: Vector2 = eng.target_goal_pos(team)
	var line_x: float = eng.L if goal.x > 1.0 else 0.0
	var shooter = _outfield(eng, team)
	eng.ball.pos = Vector2(line_x + (past if line_x > 1.0 else -past), y)
	eng.ball.z = z
	eng.ball.vz = 0.0
	eng.ball.vel = Vector2(-22.0 if line_x > 1.0 else 22.0, 0.0)
	eng.ball.shot_team = team
	eng.ball.shot_time = eng.clock
	eng.ball.shot_saved = false
	eng.ball.last_touch_id = shooter.id
	eng.ball.last_touch_team = team
	eng.ball.planned_goal = false
	eng.ball.planned_save = false
	return shooter


func test_the_frame_band_is_a_post_a_bar_or_nothing() -> void:
	var centre: float = W * 0.5
	assert_eq(MatchStats.frame_hit(centre, GOAL_W, GOAL_H, centre + GOAL_W * 0.5 + 0.05, 1.0),
		"post", "a ball wide of a post inside the contact band was not a post")
	assert_eq(MatchStats.frame_hit(centre, GOAL_W, GOAL_H, centre - GOAL_W * 0.5 - 0.10, 1.0),
		"post", "the far post was not read as a post")
	assert_eq(MatchStats.frame_hit(centre, GOAL_W, GOAL_H, centre, GOAL_H + 0.08),
		"bar", "a ball just over the bar was not a bar")
	assert_eq(MatchStats.frame_hit(centre, GOAL_W, GOAL_H, centre + 1.0, 1.0),
		"", "a ball inside the goal mouth was read as woodwork")
	assert_eq(MatchStats.frame_hit(centre, GOAL_W, GOAL_H, centre + GOAL_W * 0.5 + 1.4, 1.0),
		"", "a ball well wide was read as woodwork")
	assert_eq(MatchStats.frame_hit(centre, GOAL_W, GOAL_H, centre, GOAL_H + 1.6),
		"", "a ball well over the bar was read as woodwork")

func test_the_crossing_point_undoes_the_tick_overshoot() -> void:


	var cross: Vector2 = MatchStats.goal_plane_point(
		Vector2(105.2, 37.0), Vector2(20.0, 10.0), 1.5, 2.0, 105.0)
	assert_almost_eq(cross.x, 36.9, 0.02, "the crossing y did not undo the overshoot")
	assert_almost_eq(cross.y, 1.48, 0.02, "the crossing z did not undo the overshoot")

func test_a_shot_off_the_post_stays_in_play_and_is_counted() -> void:
	var eng := _eng(52)
	_park_keepers(eng)
	var shooter = _shot_at(eng, 0, W * 0.5 + GOAL_W * 0.5 + 0.06, 0.9)
	eng._check_rules()
	assert_eq(eng.score[0] + eng.score[1], 0, "a post was given as a goal")
	assert_eq(int(eng.stats[0]["woodwork"]), 1, "the woodwork was not counted for the shooting side")
	assert_eq(int(eng.stats[1]["woodwork"]), 0, "the defending side was credited with the woodwork")
	assert_lt(eng.ball.pos.x, eng.L, "the rebound did not come back into play")
	assert_eq(eng.phase, "play", "a post stopped play")
	assert_gte(_events(eng, "woodwork"), 1, "the post produced no commentary")
	assert_eq(int(shooter.stats["goals"]), 0, "a post credited the shooter with a goal")

func test_a_shot_off_the_bar_stays_in_play_and_is_counted() -> void:
	var eng := _eng(53)
	_park_keepers(eng)
	_shot_at(eng, 0, W * 0.5, GOAL_H + 0.07)
	eng._check_rules()
	assert_eq(eng.score[0] + eng.score[1], 0, "a ball off the bar was given as a goal")
	assert_eq(int(eng.stats[0]["woodwork"]), 1, "the bar was not counted")
	assert_eq(eng.phase, "play", "the bar stopped play")

func test_a_priced_goal_is_never_denied_by_the_frame() -> void:


	var eng := _eng(54)
	_park_keepers(eng)
	_shot_at(eng, 0, W * 0.5 + GOAL_W * 0.5 + 0.06, 0.9)
	eng.ball.planned_goal = true
	eng._check_rules()
	assert_eq(int(eng.stats[0]["woodwork"]), 0, "the frame denied a priced goal")
	assert_eq(eng.score[0] + eng.score[1], 0, "a ball outside the posts was given as a goal")

func test_a_ball_wide_of_the_frame_earns_a_restart() -> void:
	var eng := _eng(55)
	_park_keepers(eng)
	_shot_at(eng, 0, W * 0.5 + GOAL_W * 0.5 + 1.5, 0.9)
	eng._check_rules()
	assert_eq(int(eng.stats[0]["woodwork"]), 0, "a ball wide of the frame was counted as woodwork")
	assert_eq(eng.phase, "restart", "a ball wide of the posts did not stop play")


func test_an_opponent_taking_a_pass_is_credited_with_an_interception() -> void:
	var eng := _eng(56)
	var passer = _outfield(eng, 0)
	var rival = _outfield(eng, 1)
	passer.pos = Vector2(52.0, 34.0)
	eng.ball.owner_id = passer.id
	passer.has_ball = true
	eng.pass_ball(passer, Vector2(60.0, 34.0))
	eng._claim_ball(rival)
	assert_eq(int(rival.stats["interceptions"]), 1, "the interceptor was not credited")
	assert_eq(int(eng.stats[1]["interceptions"]), 1, "the intercepting side was not credited")
	assert_eq(int(passer.stats["passes_ok"]), 0, "an interception was counted as a completed pass")
	assert_eq(int(eng.ball.owner_id), rival.id, "the interceptor did not win the ball")

func test_a_team_mate_taking_a_pass_is_not_an_interception() -> void:
	var eng := _eng(57)
	var passer = _outfield(eng, 0)
	var mate = null
	for p in eng.players:
		if p.team == 0 and not p.is_gk and p.id != passer.id:
			mate = p
			break
	passer.pos = Vector2(52.0, 34.0)
	eng.ball.owner_id = passer.id
	passer.has_ball = true
	eng.pass_ball(passer, Vector2(60.0, 34.0))
	eng._claim_ball(mate)
	assert_eq(int(mate.stats["interceptions"]), 0, "a completed pass was read as an interception")
	assert_eq(int(passer.stats["passes_ok"]), 1, "the completed pass was not credited")

func test_a_ball_loose_beyond_the_window_is_not_an_interception() -> void:
	var eng := _eng(58)
	var passer = _outfield(eng, 0)
	var rival = _outfield(eng, 1)
	passer.pos = Vector2(52.0, 34.0)
	eng.ball.owner_id = passer.id
	passer.has_ball = true
	eng.pass_ball(passer, Vector2(60.0, 34.0))
	eng.clock += MatchStats.INTERCEPTION_WINDOW + 1.0
	eng._claim_ball(rival)
	assert_eq(int(rival.stats["interceptions"]), 0, "a scramble was read as an interception")

func test_a_clearance_is_not_a_pass_waiting_to_be_intercepted() -> void:
	var eng := _eng(59)
	var defender = _outfield(eng, 0)
	var rival = _outfield(eng, 1)
	defender.pos = Vector2(52.0, 34.0)
	eng.ball.owner_id = defender.id
	defender.has_ball = true
	eng.clear_ball(defender, Vector2(30.0, 34.0))
	eng._claim_ball(rival)
	assert_eq(int(rival.stats["interceptions"]), 0, "a clearance was read as an intercepted pass")


func test_momentum_credits_the_side_applying_pressure() -> void:
	var pressure: Array = [0.0, 0.0]
	for i in range(4):
		MatchStats.bump(pressure, 0, "shot", 0.25)
	var m: Vector2 = MatchStats.momentum_level(pressure)
	assert_gt(m.x, 0.8, "four good chances did not put a side on top")
	assert_lt(m.y, 0.05, "the side creating nothing read as on top")

	MatchStats.bump(pressure, 1, "save")
	assert_gt(MatchStats.momentum_level(pressure).x, m.x, "a save did not credit the attacker")
	MatchStats.bump(pressure, 1, "goal")
	assert_gt(MatchStats.momentum_level(pressure).y, 0.5, "a goal did not lift the scorer's side")

func test_momentum_fades_back_toward_nothing() -> void:
	var pressure: Array = [0.8, 0.0]
	var fade: float = MatchStats.decay(MatchStats.MOMENTUM_HALF_LIFE)
	assert_almost_eq(fade, 0.5, 0.01, "half the weight was not gone after a half-life")
	for i in range(900):
		pressure[0] = float(pressure[0]) * fade
		pressure[1] = float(pressure[1]) * fade
	assert_lt(MatchStats.momentum_level(pressure).x, 0.05, "a quiet spell kept a side on top")

func test_the_summary_reads_the_momentum_the_match_carried() -> void:
	var eng := _eng(60)
	eng._emit("shot", "Chance!", 0, null, {"xg": 0.3})
	eng._emit("shot", "Chance!", 0, null, {"xg": 0.3})
	var summary: Dictionary = eng.summary()
	assert_true(summary.has("momentum"), "the summary carries no momentum")
	var momentum: Vector2 = summary["momentum"]
	assert_gt(momentum.x, 0.5, "the side creating the chances was not on top")
	assert_lt(momentum.y, 0.05, "the side creating nothing was on top")


func test_the_broadcast_reads_the_same_momentum_as_the_summary() -> void:
	var eng := _eng(63)
	eng._emit("shot", "Chance!", 0, null, {"xg": 0.4})
	var summary: Vector2 = eng.summary()["momentum"]
	var live: Vector2 = eng.momentum_level()
	assert_eq(live, summary, "the meter and the summary read different momentum")
	assert_gt(live.x, float(0.0), "a good chance left the meter at zero")

func test_the_meter_names_the_side_carrying_play() -> void:

	assert_eq(MatchStats.momentum_leader(Vector2(0.80, 0.10)), 0, "the on-top side was not named")
	assert_eq(MatchStats.momentum_leader(Vector2(0.10, 0.80)), 1, "the away side was not named")
	assert_eq(MatchStats.momentum_leader(Vector2(0.42, 0.40)), -1, "an even match named a leader")
	assert_eq(MatchStats.momentum_leader(Vector2(0.02, 0.01)), -1, "a quiet match named a leader")
	assert_eq(MatchStats.momentum_phrase(0.80), "ON TOP", "a big spell is not read as on top")
	assert_eq(MatchStats.momentum_phrase(0.35), "PRESSING", "a normal spell lost its word")
	assert_eq(MatchStats.momentum_phrase(0.05), "", "a quiet side was given a word")

	assert_gt(MatchStats.MOMENTUM_ON_TOP, MatchStats.MOMENTUM_PRESSING, "the ladder is inverted")
	assert_lte(MatchStats.MOMENTUM_ON_TOP, 1.0, "the on-top bar is unreachable")
	assert_true(MatchStats.MOMENTUM_CLEAR_GAP > 0.0, "the clear gap must be positive")


func test_the_summary_stores_the_shared_rating() -> void:
	var eng := _eng(61)
	var p = _outfield(eng, 0)
	p.stats["goals"] = 2
	p.stats["shots"] = 3
	p.stats["passes_ok"] = 40
	eng._end_match()
	assert_almost_eq(float(p.stats["rating"]), PLSimStats.rating(p.stats), 0.001,
		"the stored rating is not the ledger's own")
	assert_gt(float(p.stats["rating"]), 6.5, "a two-goal match did not move the stored rating")


func test_priced_out_chances_can_be_struck_at_the_frame() -> void:
	var eng := _eng(62)
	var p = _outfield(eng, 0)
	var goal: Vector2 = eng.target_goal_pos(0)
	p.pos = goal + Vector2(-9.0, 0.0)
	for q in eng.players:
		if q.team == 1 and not q.is_gk:
			q.pos = Vector2(goal.x - 9.0, 4.0)
		elif q.is_gk:
			q.pos = goal + Vector2(-0.6, 0.0)
			q.cooldown = 0.0
	var at_frame := 0
	var inside := 0
	var n := 240
	for i in range(n):
		eng.rng.seed = 30000 + i
		eng.shoot_ball(p, 0.0, 0.5, 1.0)
		if eng.ball.planned_goal:
			continue
		var t: float = (goal.x - p.pos.x) / maxf(absf(eng.ball.vel.x), 0.1)
		var y_at: float = p.pos.y + eng.ball.vel.y * t
		var dy: float = absf(y_at - goal.y)
		if dy <= GOAL_W * 0.5:
			inside += 1
		elif dy <= GOAL_W * 0.5 + MatchStats.FRAME_R:
			at_frame += 1
	assert_gt(at_frame, 0, "no priced-out chance was ever struck at the frame")
	assert_lte(at_frame, int(float(n) * 0.3), "too many priced-out chances hit the frame")
	assert_gt(inside + at_frame, 0, "the chances were not aimed at the goal at all")
