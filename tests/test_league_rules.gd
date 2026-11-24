extends GdToolsTest

## League regulations: the v1 template, points from saved values, the European
## and relegation bands, and the round trip through the save's own row.

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

func test_setup_choices_are_validated() -> void:
	var r := LeagueRules.defaults("real", "every_day")
	assert_eq(str(r["calendar_mode"]), "real", "a real setup was dropped")
	assert_eq(str(r["advance_mode"]), "every_day", "an every-day setup was dropped")
	var bad := LeagueRules.defaults("nonsense", "nonsense")
	assert_eq(str(bad["calendar_mode"]), "generated", "a bad calendar mode was kept")
	assert_eq(str(bad["advance_mode"]), "fixture_days", "a bad advance mode was kept")
