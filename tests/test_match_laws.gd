extends GdToolsTest


func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk:
			return p
	return null

func _on_pitch(eng, t: int) -> int:
	var n := 0
	for p in eng.players:
		if p.team == t and not p.sent_off:
			n += 1
	return n

func _has_event(eng, kind: String) -> bool:
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			return true
	return false


func test_first_half_plays_added_time() -> void:
	var eng := MatchEngine.new(11)
	eng.phase = "play"
	eng.clock = 2701.0
	eng.tick()
	assert_gt(float(eng.added[0]), 0.0, "no first-half added time was set")
	assert_eq(eng.phase, "play", "the half ended at 45:00 with no added time")
	assert_true(eng.display_clock().contains("+"), "clock does not show added time: " + eng.display_clock())

func test_first_half_ends_after_added_time() -> void:
	var eng := MatchEngine.new(12)
	eng.phase = "play"
	eng.clock = 2701.0
	eng.tick()
	eng.clock = 2700.0 + float(eng.added[0]) + 1.0
	eng.tick()
	assert_eq(eng.phase, "half_time", "the half did not end after its added time")


func test_handball_outside_the_box_is_a_free_kick() -> void:
	var eng := MatchEngine.new(13)
	eng.phase = "play"
	var d = _outfield(eng, 0)
	d.pos = Vector2(60.0, 34.0)
	eng._award_handball(d)
	assert_eq(eng.phase, "restart", "a handball did not stop play")
	assert_eq(str(eng.restart["type"]), "free_kick", "handball outside the box should be a free kick")
	assert_eq(int(eng.restart["team"]), 1, "the free kick went to the wrong side")
	assert_eq(int(eng.stats[0]["handballs"]), 1, "the handball was not recorded")

func test_handball_inside_the_box_is_a_penalty() -> void:
	var eng := MatchEngine.new(14)
	eng.phase = "play"
	var d = _outfield(eng, 0)
	var own: Vector2 = eng.own_goal_pos(0)
	d.pos = Vector2(own.x + (10.0 if own.x < eng.L * 0.5 else -10.0), 34.0)
	assert_true(eng.in_penalty_box(d.pos, 0), "fixture did not place the defender in his own box")
	eng._award_handball(d)
	assert_eq(str(eng.restart["type"]), "penalty", "handball in the box should be a penalty")
	assert_eq(int(eng.restart["team"]), 1, "the penalty went to the wrong side")


func test_injury_costs_a_change_and_is_replaced() -> void:
	var eng := MatchEngine.new(15)
	var p = _outfield(eng, 0)
	var before: int = int(eng.teams[0]["subs_left"])
	var role: String = p.role
	eng._injure(p)
	assert_true(p.injured, "the player was not marked injured")
	assert_eq(int(eng.teams[0]["subs_left"]), before - 1, "the injury did not cost a substitution")
	assert_false(eng.players.has(p), "the injured player is still in the line-up")
	assert_eq(_on_pitch(eng, 0), 11, "the injured side was not made back up to eleven")
	var slot = null
	for q in eng.players:
		if q.team == 0 and q.role == role and not q.is_gk:
			slot = q
			break
	assert_not_null(slot, "no replacement filled the injured player's slot")
	assert_true(_has_event(eng, "injury"), "no injury line reached the event log")

func test_injury_without_changes_leaves_ten() -> void:
	var eng := MatchEngine.new(16)
	eng.teams[0]["subs_left"] = 0
	var p = _outfield(eng, 0)
	var before := _on_pitch(eng, 0)
	eng._injure(p)
	assert_true(p.sent_off, "an injured player stayed on with no change available")
	assert_eq(_on_pitch(eng, 0), before - 1, "the side did not go down to ten")


func test_referee_stays_on_the_pitch_and_whistles() -> void:
	var eng := MatchEngine.new(17)
	assert_eq(eng.referee_name, TeamData.REFEREE, "the official is not named from squad data")
	for i in range(180):
		eng.tick()
	var r = eng.referee
	assert_between(r.pos.x, 3.0, eng.L - 3.0, "the referee left the pitch: %s" % r.pos)
	assert_between(r.pos.y, 3.0, eng.W - 3.0, "the referee left the pitch: %s" % r.pos)
	eng._emit("foul", "Foul.", 0, _outfield(eng, 0))
	assert_gt(float(r.whistle), 0.0, "the referee did not whistle a foul")
	for i in range(60):
		eng.tick()
	assert_eq(float(r.whistle), 0.0, "the whistle never cleared")

func test_snapshot_carries_official_and_injury_state() -> void:
	var eng := MatchEngine.new(18)
	eng.teams[0]["subs_left"] = 0
	var p = _outfield(eng, 0)
	eng._injure(p)
	for i in range(5):
		eng.tick()
	var snap: Dictionary = eng.to_dict()
	var other := MatchEngine.new(19)
	other.from_dict(snap)
	assert_almost_eq(other.referee.pos.x, eng.referee.pos.x, 0.001, "referee position was not restored")
	assert_almost_eq(float(other.injury_timer), float(eng.injury_timer), 0.001, "injury timer was not restored")
	var got = other.by_id.get(p.id, null)
	assert_not_null(got, "the injured player vanished from the restored squad")
	assert_true(got.injured, "the injured flag was not restored")
