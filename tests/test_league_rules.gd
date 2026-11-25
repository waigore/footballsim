extends GdToolsTest

## League regulations: the v1 template, points from saved values, the European
## and relegation bands, and the round trip through the save's own row.
##
## The synthetic match report the season writes for auto-simmed fixtures rides
## with the rules that shape the season's table: seeded and repeatable, scorers
## from the front line, cards from the pivots and the back four.

func test_the_v1_template_is_this_league() -> void:
	var r := LeagueRules.defaults()
	assert_eq(int(r["win_points"]), 3, "a win is not three points")
	assert_eq(int(r["draw_points"]), 1, "a draw is not one point")
	assert_eq(int(r["ucl_places"]), 4, "UCL does not start at four places")
	assert_eq(int(r["uel_places"]), 1, "UEL is not the fifth place")
	assert_eq(int(r["uecl_places"]), 1, "UECL is not the sixth place")
	assert_eq(int(r["relegation_places"]), 3, "the drop is not three clubs")
	assert_eq(int(r["matchdays"]), 38, "a PL season is not 38 gameweeks")

func test_points_come_from_the_saved_rules() -> void:
	var r := LeagueRules.defaults()
	assert_eq(LeagueRules.points(2, 1, r), 3, "a win did not pay three")
	assert_eq(LeagueRules.points(1, 1, r), 1, "a draw did not pay one")
	assert_eq(LeagueRules.points(0, 2, r), 0, "a defeat paid something")
	var old := r.duplicate(true)
	old["win_points"] = 2
	old["draw_points"] = 1
	assert_eq(LeagueRules.points(2, 1, old), 2, "a save's own win value was ignored")

func test_table_bands_follow_the_places() -> void:
	var r := LeagueRules.defaults()
	assert_eq(LeagueRules.zone(1, r), "ucl", "1st is not a Champions League place")
	assert_eq(LeagueRules.zone(4, r), "ucl", "4th is not a Champions League place")
	assert_eq(LeagueRules.zone(5, r), "uel", "5th is not a Europa League place")
	assert_eq(LeagueRules.zone(6, r), "uecl", "6th is not a Conference League place")
	assert_eq(LeagueRules.zone(7, r), "", "7th is in Europe")
	assert_eq(LeagueRules.zone(17, r), "", "17th is already relegated")
	assert_eq(LeagueRules.zone(18, r), "relegation", "18th is not relegated")
	assert_eq(LeagueRules.zone(20, r), "relegation", "20th is not relegated")
	assert_eq(LeagueRules.zone_label("ucl"), "UCL", "the UCL band has no label")
	var places := LeagueRules.places(r)
	assert_eq(int(places["europe"]), 6, "the v1 European cut is not six clubs")

func test_normalising_a_partial_row_keeps_the_template() -> void:
	var row := {"win_points": "2", "season_start": "2027-08-14", "weekend_bias": "0.9"}
	var rules := LeagueRules.normalize(row)
	assert_eq(int(rules["win_points"]), 2, "an override did not take")
	assert_eq(str(rules["season_start"]), "2027-08-14", "the window override did not take")
	assert_almost_eq(float(rules["weekend_bias"]), 0.9, 0.001, "the weekend bias did not take")
	assert_eq(int(rules["relegation_places"]), 3, "a missing field lost its default")
	assert_eq(str(rules["advance_mode"]), "fixture_days", "a missing policy lost its default")

func test_setup_choices_are_validated() -> void:
	var r := LeagueRules.defaults("real", "every_day")
	assert_eq(str(r["calendar_mode"]), "real", "a real setup was dropped")
	assert_eq(str(r["advance_mode"]), "every_day", "an every-day setup was dropped")
	var bad := LeagueRules.defaults("nonsense", "nonsense")
	assert_eq(str(bad["calendar_mode"]), "generated", "a bad calendar mode was kept")
	assert_eq(str(bad["advance_mode"]), "fixture_days", "a bad advance mode was kept")

# ------------------------------------------------------------------------


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

## #171: some synthetic goals are converted penalties. The row is still one
## goal — the Poisson scoreline owns that — but a spot kick carries no assist,
## so the report can mark it without inventing a set-up man.
func test_penalty_goals_are_tagged_and_carry_no_assist() -> void:
	var xi := _xi()
	var goals := 0
	var penalties := 0
	for seed in range(1, 121):
		for e in MatchEvents.side(seed, "gw08-MCI-MUN", "MCI", xi, 6):
			if str(e["kind"]) != "goal":
				continue
			goals += 1
			if not bool(e.get("penalty", false)):
				continue
			penalties += 1
			assert_false(e.has("assist_id"), "a penalty carried an assist")
			assert_false(e.has("assist_name"), "a penalty carried an assist")
	assert_gt(penalties, 0, "not one synthetic goal was a penalty")
	var share := float(penalties) / float(goals)
	assert_between(share, 0.02, 0.20, "the penalty share is off the engine's own")

## The scoreline comes only from the Poisson sample: tagging a goal as a penalty
## never adds or removes one, whatever the seed.
func test_penalty_tags_never_change_the_goal_count() -> void:
	var xi := _xi()
	for seed in range(1, 61):
		var goals := 0
		for e in MatchEvents.side(seed, "gw10-BUR-MCI", "BUR", xi, 5):
			if str(e["kind"]) == "goal":
				goals += 1
		assert_eq(goals, 5, "a tagged report lost or added a goal at seed %d" % seed)

## Same save seed and fixture, same tags: the report a player reopens reads the
## way it did when the fixture settled.
func test_penalty_tags_are_seeded_with_the_report() -> void:
	var xi := _xi()
	var a := MatchEvents.side(171, "gw09-MCI-ARS", "MCI", xi, 5)
	var b := MatchEvents.side(171, "gw09-MCI-ARS", "MCI", xi, 5)
	assert_eq(a.size(), b.size(), "one seed produced two reports")
	for i in range(a.size()):
		assert_eq(bool(a[i].get("penalty", false)), bool(b[i].get("penalty", false)),
			"a penalty tag drifted between replays")
		assert_eq(str(a[i]["player_id"]), str(b[i]["player_id"]), "a scorer drifted between replays")

func _role_of(xi: Array, player_id: String) -> String:
	for p in xi:
		if str(p["id"]) == player_id:
			return str(p["role"])
	return ""
