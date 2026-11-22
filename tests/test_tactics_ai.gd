extends GdToolsTest

## The FM board reaches the pitch: a width change stretches the attacking
## shape, a formation change moves the base slots, and a role duty moves the
## player's push. Seeded engines, no UI.

func _mean_spread(eng, t: int) -> float:
	var total := 0.0
	var n := 0
	for p in eng.players:
		if p.team != t or p.is_gk or p.sent_off:
			continue
		total += absf(p.target.y - eng.W * 0.5)
		n += 1
	return total / maxf(1.0, float(n))

func _scene(seed_in: int) -> MatchEngine:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "play"
	eng.possession_team = 0
	eng.ball.pos = Vector2(eng.L * 0.5, eng.W * 0.5)
	eng.ball.owner_id = -1
	eng.ball.vel = Vector2.ZERO
	return eng

func test_width_change_stretches_the_attacking_shape() -> void:
	var eng := _scene(51)
	var t: Tactics = eng.manager.tactics_for(0)
	t.width = 0.15
	eng.live_style[0] = t.style()
	eng.brain._update_shapes()
	var narrow := _mean_spread(eng, 0)
	t.width = 0.85
	eng.live_style[0] = t.style()
	eng.brain._update_shapes()
	var wide := _mean_spread(eng, 0)
	assert_gt(wide, narrow, "width did not stretch the attacking shape")

func test_formation_change_moves_targets() -> void:
	var eng := _scene(52)
	eng.brain._update_shapes()
	var before := {}
	for p in eng.players:
		if p.team == 0:
			before[p.id] = p.target
	eng.manager._apply(0, {"formation": "3-5-2"}, "test")
	eng.brain._update_shapes()
	var moved := 0
	for p in eng.players:
		if p.team == 0 and p.target.distance_to(before[p.id]) > 0.5:
			moved += 1
	assert_gte(moved, 4, "a live formation change did not move any target")

func test_role_duty_moves_the_push() -> void:
	var eng := _scene(53)
	var st = null
	for p in eng.players:
		if p.team == 0 and p.role == "ST":
			st = p
			break
	assert_not_null(st, "the fixture has no striker")
	var base: float = Attrs.role_push("ST")
	eng.manager.tactics_for(0).roles["ST"] = "attack"
	assert_gt(eng.push_of(st), base, "attack duty did not push the striker higher")
	eng.manager.tactics_for(0).roles["ST"] = "defend"
	assert_lt(eng.push_of(st), base, "defend duty did not hold the striker")

func test_press_change_reaches_the_live_style() -> void:
	var eng := _scene(54)
	var before: float = float(eng.style_of(0)["press"])
	eng.manager._apply(0, {"press_delta": 0.15}, "test")
	assert_gt(float(eng.style_of(0)["press"]), before, "pressing change never reached MatchAI's style")

func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk and not p.sent_off:
			return p
	return null

func test_tempo_changes_pass_speed() -> void:
	var slow := _scene(55)
	var fast := _scene(55)
	slow.manager.tactics_for(0).tempo = 0.05
	fast.manager.tactics_for(0).tempo = 0.95
	slow.live_style[0] = slow.manager.tactics_for(0).style()
	fast.live_style[0] = fast.manager.tactics_for(0).style()
	var p_slow = _outfield(slow, 0)
	var p_fast = fast.by_id[p_slow.id]
	var slow_total := 0.0
	var fast_total := 0.0
	for i in range(24):
		slow.pass_ball(p_slow, p_slow.pos + Vector2(14.0, 4.0))
		fast.pass_ball(p_fast, p_fast.pos + Vector2(14.0, 4.0))
		slow_total += slow.ball.vel.length()
		fast_total += fast.ball.vel.length()
	assert_gt(fast_total, slow_total, "tempo does not change how fast the ball travels")
