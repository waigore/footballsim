extends GdToolsTest

## IFAB substitutions driven by managers: five changes, three windows (sharing a
## window at one stoppage, free at half-time), injury changes inside the laws,
## and no fixed-minute schedule left in the engine.

func _outfield(eng, t: int):
	for p in eng.players:
		if p.team == t and not p.is_gk and not p.sent_off and p.id < 200:
			return p
	return null

func _has_event(eng, kind: String) -> bool:
	for e in eng.events:
		if str(e.get("type", "")) == kind:
			return true
	return false

func _at_stoppage(seed_in: int, clock_in: float) -> MatchEngine:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "restart"
	eng.clock = clock_in
	eng.stoppage_seq = 5
	return eng

func test_five_changes_share_one_window() -> void:
	var eng := _at_stoppage(41, 2400.0)
	for i in range(5):
		var off = _outfield(eng, 0)
		assert_true(eng._bring_on(0, off, false, false, {}), "change %d was refused" % (i + 1))
	assert_eq(int(eng.teams[0]["subs_made"]), 5, "did not use the full five changes")
	assert_eq(int(eng.teams[0]["subs_left"]), 0, "subs_left was not spent")
	assert_eq(int(eng.teams[0]["windows_used"]), 1, "five changes at one stoppage should share one window")
	assert_false(eng._bring_on(0, _outfield(eng, 0), false, false, {}), "a sixth change was allowed")

func test_three_windows_then_no_more() -> void:
	var eng := _at_stoppage(42, 2400.0)
	for w in range(3):
		eng.stoppage_seq = 6 + w
		assert_true(eng._bring_on(0, _outfield(eng, 0), false, false, {}), "window %d refused" % (w + 1))
	assert_eq(int(eng.teams[0]["windows_used"]), 3, "windows were not counted")
	eng.stoppage_seq = 20
	assert_false(eng._bring_on(0, _outfield(eng, 0), false, false, {}), "a fourth window was allowed")
	assert_eq(int(eng.teams[0]["subs_made"]), 3, "the refused change still happened")
	assert_gte(int(eng.teams[0]["subs_left"]), 1, "the refused change was charged")

func test_half_time_is_a_free_window() -> void:
	var eng := _at_stoppage(43, 2700.0)
	eng.phase = "half_time"
	eng.teams[0]["windows_used"] = 3
	assert_true(eng._bring_on(0, _outfield(eng, 0), false, true, {}), "half-time change was refused")
	assert_eq(int(eng.teams[0]["windows_used"]), 3, "half-time consumed a window")
	assert_eq(int(eng.teams[0]["subs_made"]), 1, "half-time change was not counted as a change")

func test_injury_change_uses_a_change_and_a_window() -> void:
	var eng := _at_stoppage(44, 3000.0)
	var p = _outfield(eng, 0)
	eng._injure(p)
	assert_false(eng.players.has(p), "the injured player stayed on")
	assert_eq(int(eng.teams[0]["subs_made"]), 1, "the injury change was not counted")
	assert_eq(int(eng.teams[0]["subs_left"]), 4, "the injury change did not spend a substitution")
	assert_eq(int(eng.teams[0]["windows_used"]), 1, "the injury change did not use a window")
	assert_true(_has_event(eng, "injury"), "no injury line reached the log")
	assert_true(_has_event(eng, "substitution"), "no substitution line reached the log")

func test_injury_without_a_window_plays_on_short() -> void:
	var eng := _at_stoppage(45, 3000.0)
	eng.teams[0]["windows_used"] = 3
	eng.teams[0]["window_token"] = 5
	var p = _outfield(eng, 0)
	eng._injure(p)
	assert_true(p.sent_off, "the side should be down to ten with no window left")
	assert_eq(int(eng.teams[0]["subs_made"]), 0, "a windowless change was still made")

func test_manager_picks_the_change_not_the_clock() -> void:
	var eng := _at_stoppage(46, 3000.0)
	var tired = _outfield(eng, 0)
	tired.stamina = 0.30
	var made := false
	for i in range(400):
		if eng.manager._consider_subs(0, false, 0.5):
			made = true
			break
	assert_true(made, "the manager never used a change")
	assert_false(eng.players.has(tired), "the tired player was left on")
	assert_true(_has_event(eng, "substitution"), "no substitution event fired")
	var last: Dictionary = eng.manager.decisions[eng.manager.decisions.size() - 1]
	assert_eq(str(last["kind"]), "sub", "the decision log missed the change")

func test_no_scheduled_substitutions_remain() -> void:
	var eng := MatchEngine.new(47)
	eng.half = 2
	eng.clock = 4200.0
	eng.phase = "play"
	eng._tick_substitutions()
	assert_eq(int(eng.teams[0]["subs_made"]) + int(eng.teams[1]["subs_made"]), 0,
		"the fixed-minute schedule still makes changes")

func test_windows_survive_a_snapshot() -> void:
	var eng := _at_stoppage(48, 2600.0)
	eng._bring_on(0, _outfield(eng, 0), false, false, {})
	var snap: Dictionary = eng.to_dict()
	var other := MatchEngine.new(49)
	other.from_dict(snap)
	assert_eq(int(other.teams[0]["windows_used"]), int(eng.teams[0]["windows_used"]), "windows did not restore")
	assert_eq(int(other.teams[0]["window_token"]), int(eng.teams[0]["window_token"]), "window token did not restore")
	assert_eq(int(other.teams[0]["subs_made"]), int(eng.teams[0]["subs_made"]), "subs made did not restore")
	assert_eq(int(other.teams[0]["subs_left"]), int(eng.teams[0]["subs_left"]), "subs left did not restore")

func test_substituting_the_ball_carrier_keeps_possession() -> void:
	var eng := _at_stoppage(50, 3000.0)
	var off = _outfield(eng, 0)
	eng.ball.owner_id = off.id
	eng.ball.last_touch_id = off.id
	assert_true(eng._bring_on(0, off, false, false, {}), "the carrier was not replaced")
	assert_true(eng.ball.owner_id >= 200, "possession was lost when the carrier was replaced")

func test_injury_without_a_change_clears_the_ball() -> void:
	var eng := _at_stoppage(51, 3000.0)
	eng.teams[0]["windows_used"] = 3
	eng.teams[0]["window_token"] = 5
	var p = _outfield(eng, 0)
	eng.ball.owner_id = p.id
	eng._injure(p)
	assert_eq(eng.ball.owner_id, -1, "the ball stayed with a player who left injured")
