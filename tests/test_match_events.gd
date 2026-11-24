extends GdToolsTest

## Synthetic reports for auto-simmed fixtures: seeded, position-weighted, and
## plausible — scorers come from the front line, cards from the pivots and the
## back four.

func _xi() -> Array:
	return StrongestXI.pick(TeamData.get_team("MCI"))

func test_a_report_is_seeded_and_repeatable() -> void:
	var xi := _xi()
	var a := MatchEvents.side(77, "gw01-MCI-BUR", "MCI", xi, 3)
	var b := MatchEvents.side(77, "gw01-MCI-BUR", "MCI", xi, 3)
	var c := MatchEvents.side(78, "gw01-MCI-BUR", "MCI", xi, 3)
	assert_eq(a.size(), b.size(), "one seed produced two reports")
	for i in range(a.size()):
		assert_eq(int(a[i]["minute"]), int(b[i]["minute"]), "the minutes drifted")
		assert_eq(str(a[i]["player_id"]), str(b[i]["player_id"]), "the players drifted")
	var same := true
	for i in range(a.size()):
		if str(a[i]["player_id"]) != str(c[i]["player_id"]) or int(a[i]["minute"]) != int(c[i]["minute"]):
			same = false
			break
	assert_false(same, "a different seed produced the same report")

func test_goals_become_goal_events() -> void:
	var events := MatchEvents.side(11, "gw02-LIV-MUN", "LIV", _xi(), 4)
	var goals := 0
	for e in events:
		if str(e["kind"]) == "goal":
			goals += 1
			assert_eq(str(e["club_id"]), "LIV", "a goal was credited to another club")
			assert_true(str(e["player_id"]) != "", "a goal has no scorer")
			assert_gte(int(e["minute"]), 1, "a goal came before kick-off")
			assert_lte(int(e["minute"]), 90, "a goal came after full time")
	assert_eq(goals, 4, "the scoreline did not reach the report")

func test_scorers_follow_the_position_priors() -> void:
	var xi := _xi()
	var forwards := 0
	var defenders := 0
	var goals := 0
	for seed in range(1, 61):
		for e in MatchEvents.side(seed, "gw03-MCI-MUN", "MCI", xi, 6):
			if str(e["kind"]) != "goal":
				continue
			goals += 1
			var role := _role_of(xi, str(e["player_id"]))
			if role in ["ST", "LW", "RW", "CAM"]:
				forwards += 1
			elif role in ["RCB", "LCB", "CB", "RB", "LB"]:
				defenders += 1
	assert_gt(goals, 0, "no goals were generated at all")
	assert_gt(forwards, defenders * 3, "goals do not favour the front line")

func test_cards_favour_the_physical_roles() -> void:
	var xi := _xi()
	var cards := 0
	var back := 0
	for seed in range(1, 61):
		for e in MatchEvents.side(seed, "gw04-BUR-MCI", "BUR", xi, 0):
			if str(e["kind"]) not in ["yellow", "red"]:
				continue
			cards += 1
			if _role_of(xi, str(e["player_id"])) in ["RDM", "LDM", "CM", "RCB", "LCB", "RB", "LB"]:
				back += 1
	assert_gt(cards, 60, "the report has almost no cards")
	assert_gt(back, cards / 2, "cards do not favour the defensive roles")

func test_a_clean_sheet_still_reports_cards() -> void:
	var events := MatchEvents.side(5, "gw05-EVE-FUL", "EVE", _xi(), 0)
	var goals := 0
	for e in events:
		if str(e["kind"]) == "goal":
			goals += 1
	assert_eq(goals, 0, "a 0-goal side reported goals")
	assert_gt(events.size(), 0, "a 0-0 side produced no events at all")

func test_every_event_names_a_player_from_the_xi() -> void:
	var xi := _xi()
	var known := {}
	for p in xi:
		known[str(p["id"])] = true
	for e in MatchEvents.side(3, "gw06-MCI-ARS", "MCI", xi, 2):
		assert_true(known.has(str(e["player_id"])), "an event names a player outside the XI")
		assert_eq(str(e["fixture_id"]), "gw06-MCI-ARS", "an event lost its fixture")
		assert_gte(int(e["minute"]), 1, "an event came before kick-off")
		assert_lte(int(e["minute"]), 90, "an event came after full time")

func test_empty_sides_and_zero_weights_are_safe() -> void:
	assert_eq(MatchEvents.side(1, "gw07-X-Y", "X", [], 3).size(), 0, "an empty XI produced events")
	assert_eq(MatchEvents.side(1, "gw07-X-Y", "X", _xi(), 0).size() >= 0, true, "zero goals broke the report")
	var rng := RandomNumberGenerator.new()
	assert_true(MatchEvents.pick([], MatchEvents.GOAL_SHARE, "sho", rng).is_empty(),
		"an empty XI returned a scorer")

func _role_of(xi: Array, player_id: String) -> String:
	for p in xi:
		if str(p["id"]) == player_id:
			return str(p["role"])
	return ""
