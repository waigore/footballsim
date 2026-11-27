extends GdToolsTest


func _ids() -> Array:
	return TeamData.team_ids()

func test_defaults_match_club_style() -> void:
	for id in _ids():
		var data := TeamData.get_team(id)
		var t := Tactics.from_team(data, ManagerData.profile(id))
		var s: Dictionary = t.style()
		for k in ["possession", "tempo", "press", "line", "width", "directness", "crossing"]:
			assert_almost_eq(float(s[k]), float(data["style"][k]), 0.0001, "%s drifted on %s" % [id, k])

func test_every_formation_slots_the_whole_xi() -> void:
	assert_gte(TeamData.FORMATIONS.size(), 4, "the formation catalog never grew")
	for f in TeamData.FORMATIONS.keys():
		var slots: Dictionary = TeamData.slots(f)
		assert_eq(slots.size(), 11, "%s does not list eleven slots" % f)
		for role in TeamData.CANONICAL_ROLES:
			assert_true(slots.has(role), "%s has no slot for %s" % [f, role])

func test_formation_change_reslots_the_engine() -> void:
	var eng := MatchEngine.new(31)
	var before := {}
	for p in eng.players:
		if p.team == 0:
			before[p.role] = p.base
	MatchManagerTactics.apply(eng.manager, 0, {"formation": "4-4-2"}, "test")
	var moved := 0
	for p in eng.players:
		if p.team == 0 and p.base.distance_to(before[p.role]) > 0.001:
			moved += 1
	assert_gte(moved, 5, "a formation change did not move the shape")
	assert_eq(eng.manager.tactics_for(0).formation, "4-4-2", "the live formation was not stored")

func test_mentality_moves_the_style() -> void:
	var eng := MatchEngine.new(32)
	var base: Dictionary = eng.style_of(0).duplicate(true)
	MatchManagerTactics.apply(eng.manager, 0, {"mentality": "attacking"}, "test")
	var live: Dictionary = eng.style_of(0)
	assert_gt(float(live["line"]), float(base["line"]), "attacking mentality did not raise the line")
	assert_gt(float(live["press"]), float(base["press"]), "attacking mentality did not raise the press")
	assert_ne(str(eng.manager.tactics_for(0).mentality), "balanced", "mentality did not change")

func test_change_labels_read_like_football() -> void:
	var t := Tactics.from_team(TeamData.get_team("MUN"), ManagerData.profile("MUN"))
	var labels: Array = t.apply({"line_delta": 0.08, "press_delta": -0.06, "corner": "near_post"})
	assert_true(labels.has("higher line"), "line label missing: %s" % str(labels))
	assert_true(labels.has("less pressing"), "press label missing: %s" % str(labels))
	assert_true(labels.has("corners near post"), "set-piece label missing: %s" % str(labels))
	assert_gte(t.describe().size(), 2, "describe() lost the summary")

func test_tactics_snapshot_round_trip() -> void:
	var eng := MatchEngine.new(33)
	MatchManagerTactics.apply(eng.manager, 0, {"mentality": "positive", "formation": "4-3-3", "corner": "short", "roles": {"ST": "support"}}, "test")
	var snap: Dictionary = eng.to_dict()
	var other := MatchEngine.new(34)
	other.from_dict(snap)
	var a: Dictionary = eng.manager.tactics_for(0).to_dict()
	var b: Dictionary = other.manager.tactics_for(0).to_dict()
	for k in a.keys():
		assert_eq(str(a[k]), str(b[k]), "tactics key %s did not round-trip" % k)
	assert_almost_eq(float(other.style_of(0)["line"]), float(eng.style_of(0)["line"]), 0.0001, "restored style drifted")

func test_set_piece_routine_reaches_the_pitch() -> void:
	var eng := MatchEngine.new(35)
	MatchManagerTactics.apply(eng.manager, 0, {"corner": "near_post"}, "test")
	var near: float = eng._corner_aim(0)
	MatchManagerTactics.apply(eng.manager, 0, {"corner": "far_post"}, "test")
	var far: float = eng._corner_aim(0)
	assert_lt(near, far, "the corner routine does not change the aim")
	MatchManagerTactics.apply(eng.manager, 0, {"free_kick": "direct"}, "test")
	assert_eq(eng.manager.tactics_for(0).free_kick_routine(), "direct", "free-kick routine not stored")

func test_every_lever_and_description() -> void:
	var t := Tactics.from_team(TeamData.get_team("MCI"), ManagerData.profile("MCI"))
	t.line = 0.10
	t.press = 0.10
	t.width = 0.10
	t.tempo = 0.10
	t.directness = 0.90
	t.time_wasting = 0.60
	var d: Array = t.describe()
	for label in ["deeper line", "less pressing", "narrower", "slower tempo", "more direct", "time-wasting"]:
		assert_true(d.has(label), "describe missed %s: %s" % [label, str(d)])
	var labels: Array = t.apply({
		"tempo_delta": 0.2, "width_delta": 0.2, "press_delta": 0.2, "crossing_delta": -0.2,
		"directness_delta": -0.2, "line_delta": 0.05, "time_wasting": 0.0,
		"roles": {"ST": "defend", "GK": "attack"}, "opposition": {"press": "high", "marking": "man"},
		"free_kick": "direct", "corner": "short",
	})
	assert_gte(labels.size(), 6, "levers did not produce labels: %s" % str(labels))
	assert_eq(t.duty_of("ST"), "defend", "role duty not stored")
	assert_eq(t.free_kick_routine(), "direct", "free-kick routine not stored")
	assert_eq(t.corner_routine(), "short", "corner routine not stored")
	assert_eq(str(t.style()["press_trigger"]), "high", "opposition press not exposed")
	assert_eq(str(t.style()["marking"]), "man", "marking not exposed")
	var u := Tactics.from_team(TeamData.get_team("MUN"))
	u.from_dict({"mentality": "defensive"})
	assert_eq(u.mentality, "defensive", "partial from_dict lost mentality")
	assert_eq(u.formation, "4-2-3-1", "partial from_dict clobbered formation")

func test_restart_patience_honours_time_wasting() -> void:
	var eng := MatchEngine.new(36)
	eng.phase = "restart"
	eng.half = 2
	eng.clock = 4400.0
	eng.score[0] = 1
	var taker = null
	for p in eng.players:
		if p.team == 0 and not p.is_gk:
			taker = p
			break
	var plain: float = MatchRestarts.patience(eng, taker, "throw_in", 0)
	MatchManagerTactics.apply(eng.manager, 0, {"time_wasting": 0.9}, "test")
	var managed: float = MatchRestarts.patience(eng, taker, "throw_in", 0)
	assert_gt(managed, plain, "time-wasting did not buy the leader more patience")

func test_corner_and_free_kick_routines_execute() -> void:
	var eng := MatchEngine.new(37)
	eng.phase = "play"
	eng.clock = 2000.0
	MatchManagerTactics.apply(eng.manager, 0, {"corner": "short"}, "test")
	assert_eq(eng._corner_aim(0), eng.W * 0.5, "short corner routine not aimed short")
	eng._start_restart("corner", 0, Vector2(eng.L - 0.5, 0.5))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a short corner did not put the ball back in play")
	MatchManagerTactics.apply(eng.manager, 0, {"corner": "far_post"}, "test")
	eng._start_restart("corner", 0, Vector2(eng.L - 0.5, 0.5))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a far-post corner did not put the ball back in play")
	MatchManagerTactics.apply(eng.manager, 0, {"free_kick": "direct"}, "test")
	eng._start_restart("free_kick", 0, Vector2(eng.L - 24.0, eng.W * 0.5))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a direct free kick did not put the ball back in play")
	MatchManagerTactics.apply(eng.manager, 0, {"free_kick": "worked"}, "test")
	eng._start_restart("free_kick", 0, Vector2(eng.L - 40.0, 8.0))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a worked free kick did not put the ball back in play")


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
	MatchManagerTactics.apply(eng.manager, 0, {"formation": "3-5-2"}, "test")
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
	MatchManagerTactics.apply(eng.manager, 0, {"press_delta": 0.15}, "test")
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


func test_marking_band_belongs_to_the_defending_side() -> void:
	assert_almost_eq(MatchMarking.band({"marking": "zonal"}), 26.0, 0.0001, "zonal band drifted")
	assert_almost_eq(MatchMarking.band({"marking": "man"}), 30.0, 0.0001, "man band drifted")
	assert_almost_eq(MatchMarking.band({}), 26.0, 0.0001, "an unset instruction must mark like the default")


	var on_holder := _marks_in_band(0)
	var on_marker := _marks_in_band(1)
	var nobody := _marks_in_band(-1)
	assert_eq(on_holder, nobody, "the marking band follows the side holding the ball, not the side marking")
	assert_gt(on_marker, nobody, "telling the marking side to mark tight bought it no reach")

func test_man_marking_covers_the_man_it_picks_up() -> void:
	var zonal := _marks_in_band(-1)
	var man := _marks_in_band(1)
	assert_gt(man, zonal, "man marking picked up no one extra in the 26-30 m band")
	assert_gt(_target_drift(), 0.0, "the extra assignment never moved a defender onto his man")


func _marks_in_band(holder: int) -> int:
	var total := 0
	for gap in [26.5, 28.0, 29.5]:
		for ay in [0.46, 0.54, 0.62]:
			total += _marked_count(_marking_scene(gap, ay, holder), 1)
	return total


func _target_drift() -> int:
	var drifted := 0
	for gap in [26.5, 28.0, 29.5]:
		for ay in [0.46, 0.54, 0.62]:
			var z := _marking_scene(gap, ay, -1)
			var m := _marking_scene(gap, ay, 1)
			z.brain._update_shapes()
			m.brain._update_shapes()
			if _side_back(z, 1).target.distance_to(_side_back(m, 1).target) > 0.05:
				drifted += 1
	return drifted


func _marking_scene(gap: float, ay: float, holder: int) -> MatchEngine:
	var eng := _scene(56)
	for p in eng.players:
		if p.sent_off or p.is_gk:
			continue
		p.pos = Vector2(eng.L * 0.02 if p.team == 1 else eng.L * 0.98, 1.0 + float(p.id % 66))
	var own: Vector2 = eng.own_goal_pos(1)
	var dir: float = 1.0 if own.x < eng.L * 0.5 else -1.0
	var runner = _side_striker(eng, 0)
	runner.pos = own + Vector2(dir * 36.0, eng.W * ay - eng.W * 0.5)
	_side_back(eng, 1).pos = runner.pos - Vector2(dir * gap, 0.0)
	eng.ball.pos = own + Vector2(dir * 46.0, 0.0)
	if holder >= 0:
		var t: Tactics = eng.manager.tactics_for(holder)
		t.opposition["marking"] = "man"
		eng.live_style[holder] = t.style()
	eng.brain._assign_marks()
	return eng

func _side_striker(eng: MatchEngine, team: int):
	for p in eng.players:
		if p.team == team and p.role == "ST":
			return p
	return null

func _side_back(eng: MatchEngine, team: int):
	for p in eng.players:
		if p.team == team and p.role == "RCB":
			return p
	return null

func _marked_count(eng: MatchEngine, team: int) -> int:
	var n := 0
	for p in eng.players:
		if p.team == team and p.mark_id >= 0:
			n += 1
	return n
