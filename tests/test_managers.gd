extends GdToolsTest

## Manager identity and decision engine: every club has its real manager plus a
## profile, events (not ticks) drive changes, a seed always makes the same call,
## and a normal match lands near the 2–3 tactical changes per side the product
## asked for.

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
	assert_eq(eng.push_of(p), Attrs.role_push(p.role), "push_of did not fall back without a manager")
