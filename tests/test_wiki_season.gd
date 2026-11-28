extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_wiki_season")
var CACHE_DIR := TestScratch.dir("cache_test_wiki_season")
const SEED := 2027

var season: LeagueSeason = null
var first: Dictionary = {}
var scorers: Array = []

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Encyclopedia Season", "generated", "fixture_days", SEED)
	assert_not_null(season, "the season was not created")
	season.advance()
	first = season.record.fixtures.all(1)[0]
	scorers = season.record.report.top_scorers(5)

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_league_page_results_are_the_season_s_own_day() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	assert_true(_flatten(page).contains("LATEST RESULTS  ·  SEASON"), "the results block is not labelled for the season")
	var rows := _rows_below(page, "LATEST RESULTS  ·  SEASON")
	assert_eq(rows.size(), 10, "the day's ten results are not the whole table")
	var want := FixtureCalendar.day_label(str(first["kickoff"]))
	for row in rows:
		assert_eq(str(row["cells"][0]), want, "a result row is not from the season's own day")
	assert_true(_flatten(page).contains("TOP SCORERS  ·  SNAPSHOT"), "the real-world scorer chart lost its label")

func test_the_league_page_scorer_chart_is_the_season_s() -> void:
	var page := WikiModel.page(WikiModel.LEAGUE, "")
	var rows := _rows_below(page, "FOOTBALLSIM  ·  IN-SIM SCORERS")
	assert_gte(rows.size(), 1, "the season scored no goals at all")
	assert_eq(str(rows[0]["cells"][0]), str(scorers[0]["name"]), "the chart does not lead with the season's top scorer")
	assert_eq(str(rows[0]["cells"][1]), str(scorers[0]["club_name"]), "the chart names the wrong club")

func test_the_club_page_reads_the_live_row() -> void:
	var club_id := ""
	for fx in season.record.fixtures.all(1):
		if int(fx["home_goals"]) > 0:
			club_id = str(fx["home_club_id"])
			break
	assert_ne(club_id, "", "the first day scored no home goal")
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var text := _flatten(page)
	assert_true(text.contains("SEASON  ·  IN PLAY"), "the season block is not labelled as the season in play")
	assert_false(text.contains("RESULTS  ·  SNAPSHOT"), "the club page still shows the snapshot's results")
	assert_eq(_kv_value(page, "PLAYED"), "1", "the club page shows the snapshot's played count, not the season's")
	var row: Dictionary = season.record.standings.table()[_place_of(club_id)]
	assert_eq(_kv_value(page, "POINTS"), str(int(row["points"])), "the club page disagrees with the season table")
	assert_eq(_kv_value(page, "POSITION"), str(int(row["position"])), "the club page shows the wrong league place")
	var results := _rows_below(page, "RESULTS  ·  SEASON")
	assert_eq(results.size(), 1, "a club one game into the season lists the wrong number of results")
	var scorers_on_page := _rows_below(page, "IN FOOTBALLSIM  ·  SEASON SCORERS")
	assert_gte(scorers_on_page.size(), 1, "the club page has no season scorer chart")
	assert_false(text.contains("IN FOOTBALLSIM  ·  RECORD"), "the club page repeats the record the header already shows")

func test_the_player_page_reads_the_season_line() -> void:
	var scorer := str(scorers[0]["player_id"])
	var page := WikiModel.page(WikiModel.PLAYER, scorer)
	var text := _flatten(page)
	assert_true(text.contains("IN FOOTBALLSIM  ·  SEASON"), "the ledger block is not labelled for the season")
	assert_true(text.contains("SEASON  ·  %s" % PLRepository.shared().meta().get("season_label", "")), "the real-world season block lost its label")
	assert_false(text.contains("SNAPSHOT"), "the player page still talks about a snapshot")
	assert_eq(_kv_value(page, "APPS", true), "1", "the season line lost the appearance")
	assert_eq(_kv_value(page, "GOALS", true), str(int(scorers[0]["goals"])), "the season line lost his goals")
	assert_ne(_kv_value(page, "CARDS", true), "", "the season line has no cards")
	assert_eq(_kv_value(page, "RATING", true), "", "the season ledger promised a rating it does not keep")

func test_a_player_who_has_not_played_says_so() -> void:
	var club_id := str(first["home_club_id"])
	var squad := PLRepository.shared().squad(club_id)
	var unused := str(squad[squad.size() - 1]["id"])
	var page := WikiModel.page(WikiModel.PLAYER, unused)
	assert_true(_flatten(page).contains("NO APPEARANCES YET"), "an unused bench player reads as if he had played")

func test_closing_the_season_returns_the_snapshot_pages() -> void:
	season.close()
	PLRepository.shared().invalidate()
	var text := _flatten(WikiModel.page(WikiModel.LEAGUE, ""))
	assert_true(text.contains("LATEST RESULTS  ·  SNAPSHOT"), "the league page did not fall back to the snapshot")
	assert_false(text.contains("LATEST RESULTS  ·  SEASON"), "the league page kept the closed season's ledger")
	assert_eq(_kv_value(WikiModel.page(WikiModel.TEAM, "ENG-MUN1"), "PLAYED"), "11", "the club page did not fall back to the snapshot")

	season = LeagueSeason.open(LeagueSave.current.slug if LeagueSave.current != null else season.save.slug)
	assert_not_null(season, "the save could not be reopened")


func test_a_club_page_marks_an_injured_player_with_his_return_day() -> void:
	_clear_absences()
	var club_id := str(first["home_club_id"])
	var id := str(TeamData.get_team(club_id)["starters"][0]["id"])
	SeasonAvailability.injure(id, club_id, "2026-08-15", "muscle", 21, 1.0)
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var rows := _squad_rows(page)
	assert_gte(rows.size(), 18, "the squad table is missing")
	var status := ""
	var other := ""
	for row in rows:
		var cells: Array = row["cells"]
		assert_eq(cells.size(), 5, "a squad row is missing the status cell")
		if str((row["target"] as Dictionary).get("id", "")) == id:
			status = str(cells[4])
		elif other == "":
			other = str(cells[4])
	assert_eq(status, "INJ  ·  BACK 5/SEP/2026", "the injured row does not read like a calendar")
	assert_eq(other, "", "a fit player carries a status")
	var xi := StrongestXI.pick(TeamData.get_team(club_id))
	for p in xi:
		assert_ne(str(p["id"]), id, "the injured player is still in the XI")
	_clear_absences()

func test_a_ban_reads_back_from_the_fixture_that_ends_it() -> void:
	_clear_absences()
	var club_id := str(first["home_club_id"])
	var id := str(TeamData.get_team(club_id)["starters"][1]["id"])
	SeasonAvailability.suspend(id, club_id, 2, "red", "2026-08-15")
	var upcoming := PLRepository.shared().upcoming(club_id, 3)
	assert_gte(upcoming.size(), 3, "the season has too few fixtures left to read a ban")
	var want := "BAN  ·  BACK " + FixtureCalendar.day_label(str(upcoming[2]["kickoff"]))
	var status := ""
	for row in _squad_rows(WikiModel.page(WikiModel.TEAM, club_id)):
		if str((row["target"] as Dictionary).get("id", "")) == id:
			status = str(row["cells"][4])
	assert_eq(status, want, "the ban does not name the fixture it is served by")
	var profile := WikiModel.page(WikiModel.PLAYER, id)
	var shown := ""
	for block in profile["blocks"]:
		if str(block["k"]) != "kv":
			continue
		for item in block["items"]:
			if str(item[0]) == "STATUS":
				shown = str(item[1])
	assert_eq(shown, want, "the player page disagrees with the squad row")
	_clear_absences()

func test_a_fit_player_page_says_nothing_about_availability() -> void:
	_clear_absences()
	var club_id := str(first["home_club_id"])
	var rows := _squad_rows(WikiModel.page(WikiModel.TEAM, club_id))
	assert_eq((rows[0]["cells"] as Array).size(), 4, "an available squad carries a status column")
	var target: Dictionary = rows[0]["target"]
	var profile := WikiModel.page(WikiModel.PLAYER, str(target["id"]))
	var text := _flatten(profile)
	assert_false(text.contains("STATUS"), "a fit player shows a status")
	assert_false(text.contains("BACK"), "a fit player promises a return")

func test_the_return_wording_never_shows_a_day_count() -> void:
	var today := WikiAbsence.season_day()
	assert_ne(today, "", "the open season has no day")
	var derived := FixtureCalendar.day_label(FixtureCalendar.add_days(today, 10))
	assert_eq(WikiAbsence.injury_return({"kind": "injury", "due_on": "", "days_left": 10}),
		"BACK " + derived, "an injury without a due date has no return day")
	assert_eq(WikiAbsence.injury_return({"kind": "injury", "due_on": "", "days_left": 0}), "",
		"an injury with no day and no date promises a return")
	assert_eq(WikiAbsence.status({"kind": "injury", "due_on": "", "days_left": 0}, ""), "INJ",
		"a body with no known return loses its kind")
	assert_eq(WikiAbsence.status({"kind": "suspension", "matches_left": 0}, ""), "BAN",
		"a served ban still reads as out")
	var club_id := str(first["home_club_id"])
	assert_eq(WikiAbsence.ban_return(club_id, 400), "BACK AFTER SEASON",
		"a ban past the calendar names a fixture that never comes")
	assert_eq(WikiAbsence.status({"kind": "injury", "due_on": "2026-09-05"}, club_id),
		"INJ  ·  BACK 5/SEP/2026", "the return wording is not the league's date form")

func _clear_absences() -> void:
	PLDatabase.execute("DELETE FROM league_absence;")

func _squad_rows(page: Dictionary) -> Array:
	for block in page["blocks"]:
		if str(block["k"]) == "table" and (block["cols"] as Array).has("OVR"):
			return block["rows"]
	return []


func _rows_below(page: Dictionary, section: String) -> Array:
	var seen := false
	for block in page["blocks"]:
		var kind := str(block["k"])
		if kind == "section":
			if seen:
				return []
			seen = str(block["text"]) == section
			continue
		if seen and kind == "table":
			return block["rows"]
		if seen:
			return []
	return []


func _kv_value(page: Dictionary, label: String, from_last: bool = false) -> String:
	var blocks: Array = page["blocks"].duplicate()
	if from_last:
		blocks.reverse()
	for block in blocks:
		if str(block["k"]) != "kv":
			continue
		for item in block["items"]:
			if str(item[0]) == label:
				return str(item[1])
		if not from_last:
			return ""
	return ""

func _place_of(club_id: String) -> int:
	var rows := season.record.standings.table()
	for i in range(rows.size()):
		if str(rows[i]["club_id"]) == club_id:
			return i
	return 0

func _flatten(page: Dictionary) -> String:
	var text := "%s %s" % [page.get("title", ""), page.get("subtitle", "")]
	for block in page.get("blocks", []):
		text += " " + str(block.get("text", ""))
		for row in block.get("rows", []):
			text += " " + " ".join(PackedStringArray(row.get("cells", [])))
		for item in block.get("items", []):
			text += " " + str(item)
	return text

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
