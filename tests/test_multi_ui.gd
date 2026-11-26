extends GdToolsTest

## The multi-league chrome (#187/#189) without a renderer: the picker filters by
## league and allows a cross-league friendly, the hub groups a mixed day, the
## TABLES sheet tabs per league, STATS filters reports and leaders, and the
## podium frames one block per competition.

func before_all() -> void:
	PLDatabase.cache_dir = TestScratch.dir("cache_test_multi_ui")
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_picker_filters_by_league_and_mixes_sides() -> void:
	var picker = load("res://scripts/ui/team_select.gd").new()
	picker.set_league("LL")
	assert_eq(picker.ids.size(), 20, "the La Liga filter is not one league")
	for id in picker.ids:
		assert_true(str(id).begins_with("LL-"), "%s is not a La Liga club" % id)
	picker.set_league("")
	assert_eq(picker.ids.size(), 76, "the ALL filter is not every competition")
	picker.set_league("BL")
	assert_eq(picker.ids.size(), 18, "the Bundesliga filter is not one league")
	picker.set_league("BL2")
	assert_eq(picker.ids.size(), 18, "the 2. Bundesliga filter is not one league")
	for id in picker.ids:
		assert_true(str(id).begins_with("BL2-"), "%s is not a 2. Bundesliga club" % id)
	picker.set_league("")
	picker.setup("ARS", "LL-BAR")
	assert_eq(picker.home_id(), "ARS", "the home pick was lost")
	assert_eq(picker.away_id(), "LL-BAR", "a cross-league away pick was refused")
	var seen: Array = []
	picker.confirmed.connect(func(home, away): seen.append([home, away]))
	picker.confirm()
	assert_eq(seen.size(), 1, "the cross-league fixture did not confirm")
	assert_eq(str(seen[0][0]), "ARS", "the confirmed home side changed")
	assert_eq(str(seen[0][1]), "LL-BAR", "the confirmed away side changed")

func test_the_picker_offers_the_german_tiers() -> void:
	var picker = load("res://scripts/ui/team_select.gd").new()
	for pair in [["BL", 18, "BL-"], ["BL2", 18, "BL2-"]]:
		picker.set_league(str(pair[0]))
		assert_eq(picker.ids.size(), int(pair[1]), "%s filter is not one league" % pair[0])
		for id in picker.ids:
			assert_true(str(id).begins_with(str(pair[2])), "%s is not a %s club" % [id, pair[0]])
	# The chips keep their full names where they fit and fall back to codes on a
	# phone, where four competitions no longer fit as words (#242).
	assert_eq(LeagueChrome.competition_chip_label({"id": "BL", "short_name": "BUNDESLIGA"}, 150.0),
		"BUNDESLIGA", "a wide chip lost its name")
	assert_eq(LeagueChrome.competition_chip_label({"id": "BL", "short_name": "BUNDESLIGA"}, 66.0),
		"BL", "a narrow chip did not fall back to its code")
	assert_eq(LeagueChrome.competition_chip_label({"id": "BL2", "short_name": "2. BUNDESLIGA"}, 66.0),
		"2.BL", "the second tier's narrow chip is not its code")
	assert_eq(LeagueChrome.competition_chip_label({"id": "", "short_name": "ALL"}, 66.0), "ALL",
		"the ALL chip was shortened")
	picker.set_league("")

func test_a_cross_league_german_friendly_names_both_tiers() -> void:
	var mixed := PreMatchModel.build("BL-FCB", "ARS", {}, null)
	assert_eq(str(mixed["caption"]), "FRIENDLY · BUNDESLIGA v PREMIER LEAGUE",
		"a Bundesliga v Premier League friendly has no mixed caption")
	var tiers := PreMatchModel.build("BL-DOR", "BL2-BSC", {}, null)
	assert_eq(str(tiers["caption"]), "FRIENDLY · BUNDESLIGA v 2. BUNDESLIGA",
		"a cross-tier German friendly has no mixed caption")
	var same := PreMatchModel.build("BL-FCB", "BL-DOR", {}, null)
	assert_eq(str(same["caption"]), MatchBilling.FRIENDLY_CAPTION,
		"a same-league German friendly borrowed a league's round")

func test_a_cross_league_friendly_says_so() -> void:
	var mixed := PreMatchModel.build("ARS", "LL-BAR", {}, null)
	assert_eq(str(mixed["caption"]), "FRIENDLY · PREMIER LEAGUE v LA LIGA",
		"a cross-league friendly has no mixed caption")
	var same := PreMatchModel.build("ARS", "MUN", {}, null)
	assert_eq(str(same["caption"]), MatchBilling.FRIENDLY_CAPTION,
		"a same-league friendly borrowed a league's round")

func test_the_hub_groups_a_mixed_day() -> void:
	var sheet := LeagueSheet.new()
	var plan := [
		{"id": "p1", "competition_id": "PL", "matchday": 3, "kickoff": "2026-08-29",
			"home_name": "Arsenal", "away_name": "Chelsea", "home_club_id": "ARS",
			"away_club_id": "CHE", "status": "pending", "watched": 0},
		{"id": "l1", "competition_id": "LL", "matchday": 3, "kickoff": "2026-08-29",
			"home_name": "Barcelona", "away_name": "Sevilla", "home_club_id": "LL-BAR",
			"away_club_id": "LL-SEV", "status": "pending", "watched": 0},
	]
	var items: Array = sheet.hub_layout(Vector2(1280, 720), {
		"plan": plan, "interests": [], "can_suggest": false,
		"competitions": [{"id": "PL", "short": "PREMIER LEAGUE", "matchday": 3},
			{"id": "LL", "short": "LA LIGA", "matchday": 3}],
		"played": 0, "total": 760,
	})
	var heads: Array = []
	for item in items:
		if str(item["kind"]) == "league_head":
			heads.append(str(item["competition"]))
	assert_eq(heads, ["PL", "LL"], "a mixed day is not grouped by league")
	assert_eq(items.filter(func(i): return str(i["kind"]) == "table_row").size(), 0,
		"the hub still lays out a side table")

func test_the_tables_sheet_tabs_per_league() -> void:
	var table := LeagueTableView.new()
	var rows_pl: Array = []
	var rows_ll: Array = []
	for i in range(20):
		rows_pl.append({"club_id": "PL-%d" % i, "club_abbr": "P%d" % i, "position": i + 1,
			"played": 1, "won": 1, "drawn": 0, "lost": 0, "gf": 2, "ga": 0, "points": 3})
		rows_ll.append({"club_id": "LL-%d" % i, "club_abbr": "L%d" % i, "position": i + 1,
			"played": 1, "won": 1, "drawn": 0, "lost": 0, "gf": 1, "ga": 0, "points": 3})
	var view := {"table": rows_pl, "rules": {}, "interests": [],
		"competitions": [{"id": "PL", "short": "PREMIER LEAGUE"}, {"id": "LL", "short": "LA LIGA"}]}
	var items: Array = table.layout(Vector2(1280, 720), view)
	var tabs: Array = []
	for item in items:
		if str(item["kind"]) == "chip":
			tabs.append(str(item["id"]))
	assert_eq(tabs, ["tbl:league:PL", "tbl:league:LL"], "the table has no league tabs")
	assert_true(table.press("tbl:league:LL", null), "the La Liga tab took no press")
	assert_eq(table.league_tab, "LL", "the table stayed on the first league")
	assert_false(table.press("tbl:league:LL", null), "a repeated tab press repainted")

func test_stats_filters_reports_and_leaders() -> void:
	var extra := LeagueExtra.new()
	var view := {
		"filters": {"league": "LL", "month": "", "team": "BAR", "stat": "assists"},
		"competitions": [{"id": "PL", "short": "PREMIER LEAGUE"}, {"id": "LL", "short": "LA LIGA"}],
		"reports": [], "leaders": [{"name": "L. Yamal", "abbr": "BAR", "competition_id": "LL",
			"goals": 3, "assists": 7, "stat_value": 7}],
		"complete": false,
	}
	var items: Array = extra.stats_layout(Vector2(1280, 720), view)
	var ids: Array = []
	for item in items:
		ids.append(str(item["id"]))
	assert_has(ids, "statsleague:LL", "the league filter has no selected league")
	assert_has(ids, "statsstat:assists", "the leader stat door is missing")
	assert_has(ids, "statsteam", "the team filter field is missing")
	var leaders := 0
	for item in items:
		if str(item["kind"]) == "leader":
			leaders += 1
			assert_eq(int((item["row"] as Dictionary)["stat_value"]), 7,
				"the assists chart printed another stat")
	assert_eq(leaders, 1, "the leader chart row is missing")

func test_the_podium_frames_one_block_per_league() -> void:
	var book := LeagueBook.new()
	var one := {"champion": {"club": "A", "points": 1}, "runner_up": {"club": "B", "points": 0},
		"europe": [], "relegated": []}
	var summary := {"competitions": [one, one], "champion": one["champion"],
		"runner_up": one["runner_up"], "europe": [], "relegated": []}
	var two_h: float = book.frame_height({"summary": summary})
	var one_h: float = book.frame_height({"summary": one})
	assert_gt(two_h, one_h * 1.8, "the podium did not make room for a second league")
	assert_eq(LeagueBook._podium_sections(summary).size(), 2, "the podium lost a league block")

func test_the_podium_makes_room_for_the_promoting_tier_and_the_tie() -> void:
	var book := LeagueBook.new()
	var second := {"champion": {"club": "A", "points": 1}, "runner_up": {"club": "B", "points": 0},
		"europe": [], "relegated": [{"club": "C"}], "table": [],
		"rules": {"promotion_places": 2, "promotion_playoff_places": 1}}
	var plain := {"champion": {"club": "A", "points": 1}, "runner_up": {"club": "B", "points": 0},
		"europe": [], "relegated": [{"club": "C"}], "table": [], "rules": {}}
	var with_up: float = book.frame_height({"summary": second})
	var without: float = book.frame_height({"summary": plain})
	assert_gt(with_up, without, "a promoting tier painted without room")
	var tied := {"competitions": [plain, second], "relegation": {"text": "A 2 – 1 B"}}
	var untied := {"competitions": [plain, second]}
	assert_gt(book.frame_height({"summary": tied}), book.frame_height({"summary": untied}),
		"the Relegation block painted without room")

func test_the_stats_doors_write_their_filter() -> void:
	var screen := FakeStats.new()
	screen.stats_filter = {"league": "", "month": "", "team": "", "stat": "goals"}
	assert_true(LeagueStatsActions.press(screen, "statsleague:LL"), "the league door was not handled")
	assert_eq(str(screen.stats_filter["league"]), "LL", "the league filter did not change")
	assert_true(LeagueStatsActions.press(screen, "statsstat:assists"), "the stat door was not handled")
	assert_eq(str(screen.stats_filter["stat"]), "assists", "the leader stat did not change")
	assert_true(LeagueStatsActions.press(screen, "statsteam"), "the team field press was not handled")
	assert_false(LeagueStatsActions.press(screen, "back"), "a foreign door was swallowed")
	assert_eq(screen.refreshes, 3, "a filter door did not repaint")
	# A month step reads the clock only while a season is open; with none it still
	# answers the press without inventing a date.
	assert_true(LeagueStatsActions.press(screen, "statsmonth:1"), "the month door was not handled")
	assert_eq(str(screen.stats_filter["month"]), "", "a month was invented with no season")

func test_the_month_door_steps_from_the_clock() -> void:
	var season := LeagueSeason.create("Month World", "generated", "fixture_days", 9101, ["PL"])
	assert_not_null(season, "the month season was not created")
	var screen := FakeStats.new()
	screen.season = season
	screen.stats_filter = {"league": "", "month": "", "team": "", "stat": "goals"}
	assert_true(LeagueStatsActions.press(screen, "statsmonth:1"), "the month door was not handled")
	var date := str(season.state().get("date", ""))
	var base := date.substr(0, 7)
	assert_eq(str(screen.stats_filter["month"]), LeagueMonth.shift(base, 1),
		"the month door did not step once from the clock")
	season.close()

func test_the_wizard_league_toggle_keeps_one_on() -> void:
	var screen := FakeWizard.new()
	LeagueWizardActions.toggle_league(screen, "PL")
	assert_eq(screen.wizard["competitions"], ["PL"], "the wizard switched its only league off")
	LeagueWizardActions.toggle_league(screen, "LL")
	assert_eq(screen.wizard["competitions"], ["PL", "LL"], "La Liga did not join the wizard")
	assert_eq(screen.refreshes, 1, "the wizard did not repaint after a pick")
	LeagueWizardActions.toggle_league(screen, "PL")
	assert_eq(screen.wizard["competitions"], ["LL"], "the Premier League did not come off")
	LeagueWizardActions.toggle_league(screen, "")
	assert_eq(screen.wizard["competitions"], ["LL"], "an empty id changed the set")

func test_the_system_sheet_can_switch_the_advance_mode() -> void:
	var season := LeagueSeason.create("Advance World", "generated", "fixture_days", 9102, ["PL", "LL"])
	assert_not_null(season, "the advance season was not created")
	var screen := FakeSys.new()
	screen.season = season
	screen.sys = {"status": "", "error": ""}
	LeagueSystemActions.toggle_advance(screen)
	assert_eq(season.save.advance_mode(), "every_day", "the clock policy did not switch")
	assert_true(str(screen.sys["status"]).begins_with("ADVANCE:"), "the switch was silent")
	LeagueSystemActions.toggle_advance(screen)
	assert_eq(season.save.advance_mode(), "fixture_days", "the clock policy did not switch back")
	season.close()

class FakeStats:
	var stats_filter := {}
	var season = null
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1

class FakeWizard:
	var wizard := {"competitions": ["PL"]}
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1

class FakeSys:
	var season = null
	var sys := {}
	var refreshes := 0

	func refresh() -> void:
		refreshes += 1
