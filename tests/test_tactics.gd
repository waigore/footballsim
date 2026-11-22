extends GdToolsTest

## FM tactics slice: the club style survives as the default, formations re-slot
## the same XI, mentality moves the effective style, and the whole board rides
## the match snapshot.

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
	eng.manager._apply(0, {"formation": "4-4-2"}, "test")
	var moved := 0
	for p in eng.players:
		if p.team == 0 and p.base.distance_to(before[p.role]) > 0.001:
			moved += 1
	assert_gte(moved, 5, "a formation change did not move the shape")
	assert_eq(eng.manager.tactics_for(0).formation, "4-4-2", "the live formation was not stored")

func test_mentality_moves_the_style() -> void:
	var eng := MatchEngine.new(32)
	var base: Dictionary = eng.style_of(0).duplicate(true)
	eng.manager._apply(0, {"mentality": "attacking"}, "test")
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
	eng.manager._apply(0, {"mentality": "positive", "formation": "4-3-3", "corner": "short", "roles": {"ST": "support"}}, "test")
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
	eng.manager._apply(0, {"corner": "near_post"}, "test")
	var near: float = eng._corner_aim(0)
	eng.manager._apply(0, {"corner": "far_post"}, "test")
	var far: float = eng._corner_aim(0)
	assert_lt(near, far, "the corner routine does not change the aim")
	eng.manager._apply(0, {"free_kick": "direct"}, "test")
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
	var plain: float = eng._restart_patience(taker, "throw_in", 0)
	eng.manager._apply(0, {"time_wasting": 0.9}, "test")
	var managed: float = eng._restart_patience(taker, "throw_in", 0)
	assert_gt(managed, plain, "time-wasting did not buy the leader more patience")

func test_corner_and_free_kick_routines_execute() -> void:
	var eng := MatchEngine.new(37)
	eng.phase = "play"
	eng.clock = 2000.0
	eng.manager._apply(0, {"corner": "short"}, "test")
	assert_eq(eng._corner_aim(0), eng.W * 0.5, "short corner routine not aimed short")
	eng._start_restart("corner", 0, Vector2(eng.L - 0.5, 0.5))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a short corner did not put the ball back in play")
	eng.manager._apply(0, {"corner": "far_post"}, "test")
	eng._start_restart("corner", 0, Vector2(eng.L - 0.5, 0.5))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a far-post corner did not put the ball back in play")
	eng.manager._apply(0, {"free_kick": "direct"}, "test")
	eng._start_restart("free_kick", 0, Vector2(eng.L - 24.0, eng.W * 0.5))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a direct free kick did not put the ball back in play")
	eng.manager._apply(0, {"free_kick": "worked"}, "test")
	eng._start_restart("free_kick", 0, Vector2(eng.L - 40.0, 8.0))
	eng._execute_restart()
	assert_eq(eng.phase, "play", "a worked free kick did not put the ball back in play")
