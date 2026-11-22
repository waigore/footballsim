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
