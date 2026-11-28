extends GdToolsTest


func _duel(level: float, trials: int, seed_in: int = 4242) -> Dictionary:
	var eng := MatchEngine.new(seed_in, "ENG-MUN1", "ENG-MCI1")
	eng.phase = "play"
	eng.possession_team = 0
	var def = null
	for q in eng.players:
		if q.team == 1 and not q.is_gk:
			def = q
			break
	var carrier = null
	for q in eng.players:
		if q.team == 0 and not q.is_gk:
			carrier = q
			break
	var style: Dictionary = eng.style_of(1).duplicate()
	style["aggression"] = level
	eng.live_style[1] = style
	var dir := float(eng.teams[0]["dir"])
	var spot: Vector2 = eng.own_goal_pos(0) + Vector2(dir * 25.0, 0.0)
	var won := 0
	var fouls := 0
	for i in range(trials):
		carrier.pos = spot
		carrier.vel = Vector2.ZERO
		carrier.has_ball = true
		carrier.cooldown = 0.0
		carrier.sent_off = false
		def.pos = spot - Vector2(dir * 1.2, 0.0)
		def.vel = Vector2.ZERO
		def.facing = Vector2(dir, 0.0)
		def.cooldown = 0.0
		def.sent_off = false
		def.yellow = 0
		eng.ball.pos = spot
		eng.ball.owner_id = carrier.id
		eng.ball.vel = Vector2.ZERO
		eng.ball.shot_team = -1
		var t0: int = int(def.stats["tackles"])
		var f0: int = int(eng.stats[1]["fouls"])
		eng._attempt_tackle(def, carrier)
		won += int(def.stats["tackles"]) - t0
		fouls += int(eng.stats[1]["fouls"]) - f0
	return {"won": won, "fouls": fouls}


func test_the_seed_ships_a_per_club_aggression_bar() -> void:
	var seen := {}
	for id in TeamData.team_ids():
		var data := TeamData.get_team(id)
		var style: Dictionary = data.get("style", {})
		assert_true(style.has("aggression"), "%s ships no aggression bar" % id)
		var bar := float(style["aggression"])
		assert_true(bar >= 0.0 and bar <= 1.0, "%s has an aggression bar outside 0..1 (%.2f)" % [id, bar])
		seen[bar] = true
	assert_gt(seen.size(), 1, "every club ships the same aggression, so the bar cannot be a style")


func test_the_neutral_bar_changes_nothing() -> void:
	assert_almost_eq(MatchContact.tackle_bonus({"aggression": MatchContact.NEUTRAL}), 0.0, 1e-9,
		"the neutral bar moved the tackle chance")
	assert_almost_eq(MatchContact.foul_multiplier({"aggression": MatchContact.NEUTRAL}), 1.0, 1e-9,
		"the neutral bar moved the foul chance")


	assert_almost_eq(MatchContact.tackle_bonus({}), 0.0, 1e-9,
		"a style without an aggression bar did not fall back to neutral")
	assert_almost_eq(MatchContact.foul_multiplier({}), 1.0, 1e-9,
		"a style without an aggression bar changed the foul chance")


func test_aggression_leans_both_halves_of_a_challenge() -> void:
	var low: float = MatchContact.tackle_bonus({"aggression": 0.0})
	var mid: float = MatchContact.tackle_bonus({"aggression": MatchContact.NEUTRAL})
	var high: float = MatchContact.tackle_bonus({"aggression": 1.0})
	assert_lt(low, mid, "a passive side was given the same tackle chance")
	assert_gt(high, mid, "an aggressive side was given no more tackle chance")
	assert_lt(MatchContact.foul_multiplier({"aggression": 0.0}),
		MatchContact.foul_multiplier({"aggression": 1.0}),
		"aggression did not also raise the foul risk, so it is a free upgrade")


func test_the_shipped_spread_is_worth_something() -> void:
	var weakest: float = MatchContact.tackle_bonus({"aggression": 0.48})
	var strongest: float = MatchContact.tackle_bonus({"aggression": 0.62})
	assert_gt(strongest - weakest, 0.015,
		"the shipped clubs' own aggression spread is worth nothing (%0.3f)" % (strongest - weakest))
	var high_foul: float = MatchContact.foul_multiplier({"aggression": 0.62})
	var low_foul: float = MatchContact.foul_multiplier({"aggression": 0.48})
	assert_gt(high_foul - low_foul, 0.05,
		"the shipped aggression spread does not move the foul risk")


func test_the_whole_range_moves_a_challenge_plainly() -> void:
	var high: float = MatchContact.tackle_bonus({"aggression": 1.0})
	var low: float = MatchContact.tackle_bonus({"aggression": 0.0})
	var span: float = high - low
	assert_gt(span, 0.10, "the whole aggression range barely moves the tackle chance (%0.2f)" % span)
	assert_lt(span, 0.20, "the whole aggression range swamps a challenge (%0.2f)" % span)


func test_the_bar_reaches_the_staged_challenge() -> void:
	var passive: Dictionary = _duel(0.0, 240)
	var aggressive: Dictionary = _duel(1.0, 240)
	assert_gt(int(aggressive["won"]), int(passive["won"]),
		"an aggressive side won no more of the same challenges (%d vs %d)" % [
			int(aggressive["won"]), int(passive["won"])])
	assert_gt(int(aggressive["fouls"]), int(passive["fouls"]),
		"an aggressive side gave away no more of the same challenges (%d vs %d)" % [
			int(aggressive["fouls"]), int(passive["fouls"])])
