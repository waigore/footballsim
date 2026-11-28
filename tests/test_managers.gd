extends GdToolsTest


func test_every_club_has_its_real_manager_and_a_profile() -> void:
	var reacts := {}
	for id in TeamData.team_ids():
		var data := TeamData.get_team(id)
		var p: Dictionary = ManagerData.profile(id)
		assert_true(ManagerData.has_full_profile(p), "%s profile is incomplete" % id)
		assert_eq(str(p["name"]), str(data["manager"]), "%s is bound to the wrong manager" % id)
		assert_false(str(p["name"]) == "", "%s has no manager name" % id)
		for k in ["reactive", "stubborn", "risk", "patience", "sub_style"]:
			assert_between(float(p[k]), 0.0, 1.0, "%s %s out of range" % [id, k])
		assert_gte((p["levers"] as Array).size(), 1, "%s has no preferred levers" % id)
		assert_true(TeamData.FORMATIONS.has(str(p["formation"])), "%s prefers an unknown formation" % id)
		assert_true(Tactics.MENTALITIES.has(str(p["mentality"])), "%s prefers an unknown mentality" % id)
		reacts[snappedf(float(p["reactive"]), 0.05)] = true
	assert_gte(reacts.size(), 8, "manager profiles are not distinct enough to feel different")

func test_only_the_authored_clubs_carry_a_persona() -> void:
	for id in ManagerData.PROFILES.keys():
		assert_true(ManagerData.has_persona(str(id)), "%s lost its authored temperament" % str(id))
	for id in ["ESP-BAR1", "GER-FCB1", "GER-BSC1"]:
		assert_false(ManagerData.has_persona(id), "%s claims a temperament the snapshot never recorded" % id)
	assert_eq(ManagerData.profile("ESP-BAR1")["name"], "H. Flick", "the snapshot club lost its real manager")

func _timeline(seed_in: int, count: int) -> Array:
	var r := RandomNumberGenerator.new()
	r.seed = seed_in
	var out := []
	var minute := 9
	for i in range(count):
		out.append({
			"minute": minute, "team": r.randi_range(0, 1),
			"kind": "goal" if r.randf() < 0.60 else "card", "red": r.randf() < 0.12,
		})
		minute += r.randi_range(3, 8)
	return out

func _replay(seed_in: int, timeline: Array) -> Array:
	var eng := MatchEngine.new(seed_in)
	eng.phase = "play"
	var goals := [0, 0]
	for ev in timeline:
		eng.clock = float(ev["minute"]) * 60.0
		var t: int = int(ev["team"])
		if str(ev["kind"]) == "goal":
			goals[t] += 1
			eng.score[0] = int(goals[0])
			eng.score[1] = int(goals[1])
			eng.manager.on_event("goal", {"team": t})
		else:
			eng.manager.on_event("card", {"team": t, "red": bool(ev["red"])})
		eng.manager.tick(60.0)
	return [int(eng.manager.changes[0]), int(eng.manager.changes[1])]

func test_same_seed_same_managerial_decisions() -> void:
	var tl := _timeline(77, 18)
	var eng_a := MatchEngine.new(77)
	eng_a.phase = "play"
	var eng_b := MatchEngine.new(77)
	eng_b.phase = "play"
	var goals := [0, 0]
	for ev in tl:
		for eng in [eng_a, eng_b]:
			eng.clock = float(ev["minute"]) * 60.0
			var t: int = int(ev["team"])
			if str(ev["kind"]) == "goal":
				goals[t] += 1
				eng.score[0] = int(goals[0])
				eng.score[1] = int(goals[1])
				eng.manager.on_event("goal", {"team": t})
			else:
				eng.manager.on_event("card", {"team": t, "red": bool(ev["red"])})
			eng.manager.tick(60.0)
	assert_eq(str(eng_a.manager.decisions), str(eng_b.manager.decisions), "the same seed produced different decisions")
	for t in range(2):
		assert_eq(str(eng_a.manager.tactics_for(t).to_dict()), str(eng_b.manager.tactics_for(t).to_dict()),
			"tactics diverged on the same seed")

func test_typical_match_changes_tactics_two_to_three_times() -> void:
	var total := 0
	var worst := 0
	var matches := 60
	for i in range(matches):
		var counts := _replay(i + 1, _timeline(i + 1, 18))
		total += int(counts[0]) + int(counts[1])
		worst = maxi(worst, maxi(int(counts[0]), int(counts[1])))
		assert_lte(int(counts[0]), MatchManager.TACTICS_CAP, "home side exceeded the tactics cap")
		assert_lte(int(counts[1]), MatchManager.TACTICS_CAP, "away side exceeded the tactics cap")
	var per_side := float(total) / float(matches * 2)
	assert_between(per_side, 1.4, 3.0, "calibration drifted: %.2f tactics changes per side" % per_side)
	assert_lte(worst, MatchManager.TACTICS_CAP, "a side changed tactics more than three times")

func test_tactics_are_event_driven_not_per_tick() -> void:
	var eng := MatchEngine.new(88)
	eng.phase = "play"
	eng.clock = 120.0
	for i in range(900):
		eng.manager.tick(1.0 / 60.0)
	assert_eq(int(eng.manager.changes[0]) + int(eng.manager.changes[1]), 0, "managers tinkered with nothing happening")

func test_a_red_card_draws_a_reaction_across_seeds() -> void:
	var reacted := 0
	for i in range(40):
		var eng := MatchEngine.new(300 + i)
		eng.phase = "play"
		eng.clock = 3600.0
		eng.manager.on_event("card", {"team": 0, "red": true})
		if int(eng.manager.changes[0]) > 0:
			reacted += 1
			var last: Dictionary = eng.manager.decisions[eng.manager.decisions.size() - 1]
			assert_eq(str(last["kind"]), "tactics", "a red card did not produce a tactics decision")
	assert_gte(reacted, 3, "no manager reacted to a red card in 40 matches")

func test_reactive_profiles_change_more_than_stubborn_ones() -> void:
	var hot := 0
	var cold := 0
	for i in range(8):
		var tl := _timeline(500 + i, 18)
		var a := MatchEngine.new(500 + i)
		a.phase = "play"
		a.manager.profiles[0] = {"reactive": 0.95, "stubborn": 0.10, "risk": 0.6, "patience": 0.4,
			"sub_style": 0.6, "levers": ["mentality", "press"], "formation": "4-2-3-1",
			"mentality": "positive", "trait": "touchline", "name": "A"}
		a.manager.profiles[1] = a.manager.profiles[0]
		var b := MatchEngine.new(500 + i)
		b.phase = "play"
		b.manager.profiles[0] = {"reactive": 0.10, "stubborn": 0.90, "risk": 0.4, "patience": 0.8,
			"sub_style": 0.4, "levers": ["line"], "formation": "4-2-3-1",
			"mentality": "cautious", "trait": "stubborn", "name": "B"}
		b.manager.profiles[1] = b.manager.profiles[0]
		hot += _count_replay(a, tl)
		cold += _count_replay(b, tl)
	assert_gt(hot, cold, "manager temperament does not bias the number of changes")

func _count_replay(eng, timeline: Array) -> int:
	var goals := [0, 0]
	for ev in timeline:
		eng.clock = float(ev["minute"]) * 60.0
		var t: int = int(ev["team"])
		if str(ev["kind"]) == "goal":
			goals[t] += 1
			eng.score[0] = int(goals[0])
			eng.score[1] = int(goals[1])
			eng.manager.on_event("goal", {"team": t})
		else:
			eng.manager.on_event("card", {"team": t, "red": bool(ev["red"])})
		eng.manager.tick(60.0)
	return int(eng.manager.changes[0]) + int(eng.manager.changes[1])

func test_manager_state_survives_a_snapshot() -> void:
	var eng := MatchEngine.new(99)
	eng.phase = "play"
	eng.clock = 3600.0
	eng.manager.on_event("card", {"team": 1, "red": true})
	var snap: Dictionary = eng.to_dict()
	var other := MatchEngine.new(98)
	other.from_dict(snap)
	assert_eq(other.manager.changes, eng.manager.changes, "tactics counts did not round-trip")
	assert_eq(str(other.manager.tactics_for(1).to_dict()), str(eng.manager.tactics_for(1).to_dict()),
		"tactics board did not round-trip")

func test_a_card_tells_the_dugout() -> void:
	var eng := MatchEngine.new(95)
	eng.phase = "play"
	eng.clock = 1200.0
	var p = null
	for q in eng.players:
		if q.team == 0 and not q.is_gk:
			p = q
			break
	eng._send_off_or_book(p, "yellow")
	var seen := false
	for e in eng.events:
		if str(e.get("type", "")) == "card":
			seen = true
	assert_true(seen, "a card never reached the event log")

func test_push_falls_back_without_a_manager() -> void:
	var eng := MatchEngine.new(96)
	var p = null
	for q in eng.players:
		if q.team == 0 and not q.is_gk:
			p = q
			break
	eng.manager = null
	assert_eq(eng.push_of(p), AttrRoles.role_push(p.role), "push_of did not fall back without a manager")


func test_patience_sets_the_wait_above_the_legal_floor() -> void:


	assert_eq(MatchCadence.tactics_gap({"patience": MatchCadence.NEUTRAL_PATIENCE}),
		MatchCadence.MIN_GAP, "the neutral profile did not sit on the seven-minute floor")
	assert_eq(MatchCadence.tactics_gap({}), MatchCadence.MIN_GAP,
		"a profile without a patience value did not read as neutral")

	for low in [0.0, 0.20, 0.40]:
		assert_eq(MatchCadence.tactics_gap({"patience": low}), MatchCadence.MIN_GAP,
			"patience %.2f went below the seven-minute law floor" % low)

	var waits: Array = []
	for p in [0.52, 0.56, 0.60, 0.66, 1.0]:
		waits.append(MatchCadence.tactics_gap({"patience": p}))
	for i in range(1, waits.size()):
		assert_gt(float(waits[i]), float(waits[i - 1]),
			"more patience did not buy more wait: %s" % str(waits))

	var patient: float = MatchCadence.tactics_gap({"patience": 0.66})
	assert_between(patient, MatchCadence.MIN_GAP * 1.3, MatchCadence.MIN_GAP * 1.6,
		"the most patient shipped profile's wait is outside the fitted band")

func test_the_patience_lever_reaches_the_dugout() -> void:


	var eng := MatchEngine.new(4101)
	eng.phase = "play"
	eng.clock = 3000.0
	eng.manager.profiles[0]["patience"] = 0.66
	eng.manager.last_change[0] = 3000.0 - 450.0
	var quiet := 0
	for i in range(200):
		if MatchManagerTactics.consider(eng.manager, 0, "chasing", 0.9):
			quiet += 1
	assert_eq(quiet, 0, "a patient manager acted inside his own wait (450s of 596s)")
	eng.manager.last_change[0] = 3000.0 - 620.0
	var acted := false
	for i in range(200):
		if MatchManagerTactics.consider(eng.manager, 0, "chasing", 0.9):
			acted = true
			break
	assert_true(acted, "a patient manager never acted once his wait had passed")

func test_the_default_side_keeps_its_shipped_wait() -> void:


	var impatient := 0
	for id in TeamData.team_ids():
		var prof: Dictionary = ManagerData.profile(id)
		var gap: float = MatchCadence.tactics_gap(prof)
		if float(prof.get("patience", 0.52)) <= MatchCadence.NEUTRAL_PATIENCE:
			assert_eq(gap, MatchCadence.MIN_GAP, "%s does not wait the shipped seven minutes" % id)
			impatient += 1
		else:
			assert_gt(gap, MatchCadence.MIN_GAP, "%s's patience bought no extra wait" % id)
	assert_gte(impatient, 8, "almost no shipped club still waits the flat seven minutes")

func test_a_patient_manager_changes_less_often_than_an_impatient_one() -> void:


	var patient := 0
	var impatient := 0
	for i in range(12):
		var tl := _timeline(700 + i, 18)
		var a := MatchEngine.new(700 + i)
		a.phase = "play"
		a.manager.profiles[0]["patience"] = 0.10
		a.manager.profiles[1]["patience"] = 0.10
		var b := MatchEngine.new(700 + i)
		b.phase = "play"
		b.manager.profiles[0]["patience"] = 0.95
		b.manager.profiles[1]["patience"] = 0.95
		var counts_a: Array = _count_both(a, tl)
		var counts_b: Array = _count_both(b, tl)
		impatient += int(counts_a[0]) + int(counts_a[1])
		patient += int(counts_b[0]) + int(counts_b[1])
	assert_lt(patient, impatient,
		"the patience lever does not change how often a manager acts (%d vs %d)" % [patient, impatient])


func _count_both(eng, timeline: Array) -> Array:
	var goals := [0, 0]
	for ev in timeline:
		eng.clock = float(ev["minute"]) * 60.0
		var t: int = int(ev["team"])
		if str(ev["kind"]) == "goal":
			goals[t] += 1
			eng.score[0] = int(goals[0])
			eng.score[1] = int(goals[1])
			eng.manager.on_event("goal", {"team": t})
		else:
			eng.manager.on_event("card", {"team": t, "red": bool(ev["red"])})
		eng.manager.tick(60.0)
	return [int(eng.manager.changes[0]), int(eng.manager.changes[1])]


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
		if MatchManagerSubs.consider(eng.manager, 0, false, 0.5):
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
