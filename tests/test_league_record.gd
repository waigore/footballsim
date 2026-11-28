extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_record_split")
var CACHE_DIR := TestScratch.dir("cache_test_record_split")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	LeagueSave.close()
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR

func _clean() -> void:
	for dir in [SAVE_DIR, CACHE_DIR]:
		var entry := DirAccess.open(dir)
		if entry == null:
			continue
		for name in entry.get_files():
			entry.remove(name)

func _season() -> LeagueSeason:
	return LeagueSeason.create("Record Split", "generated", "fixture_days", 2027)

func test_the_fixtures_door_installs_a_calendar_before_the_clips_exist() -> void:
	var season := _season()
	assert_not_null(season, "the season was not created")
	var fixtures := season.record.fixtures
	assert_eq(fixtures.all().size(), 380, "the calendar is not a full season")
	assert_eq(fixtures.all(1).size(), 10, "gameweek one is short")
	assert_eq(fixtures.unplayed(), 380, "a new season already counted played games")
	assert_eq(fixtures.on(season.save.current_date()).size(), 10,
		"the clock's day does not hold its matchday")
	var dates := fixtures.dates()
	assert_true(not dates.is_empty(), "the calendar has no dates")
	assert_eq(str(dates[0]), str(season.save.current_date()), "the first date is not the clock's day")
	season.close()

func test_another_season_wears_its_own_slug() -> void:
	var season := _season()
	assert_not_null(season, "the season was not created")
	var twin := LeagueSeason.create("Record Split", "generated", "fixture_days", 2027)
	assert_not_null(twin, "the second season was not created")
	assert_true(twin.record != season.record, "two seasons shared one ledger")
	assert_true(twin.save != season.save, "two seasons shared one save")
	assert_eq(season.matches_remaining(), 380, "the first season lost its calendar")
	assert_eq(season.record.fixtures.all().size(), 380, "the first season lost its fixtures")
	twin.close()
	season.close()

func test_unknown_fixture_ids_are_refused() -> void:
	var season := _season()
	assert_not_null(season, "the season was not created")
	assert_true(not season.set_interest("", true), "an empty club reached the shortlist")
	var missing := season.record.fixtures.one("gw99-NONE-NONE")
	assert_true(missing.is_empty(), "an unknown fixture came back as a row")
	assert_true(season.report("gw99-NONE-NONE").is_empty(), "an unknown fixture made a report")
	assert_true(season.start_watch("gw99-NONE-NONE").is_empty(), "an unknown fixture took a watch")
	season.close()

func test_a_result_and_recompute_repair_the_table() -> void:
	var season := _season()
	assert_not_null(season, "the season was not created")
	var fx: Dictionary = season.plan()[0]
	var id := str(fx["id"])


	PLDatabase.execute(
		"UPDATE league_table SET home_gf = 999, away_played = 0, points = 0 "
		+ "WHERE club_id = ? OR club_id = ?;",
		[str(fx["home_club_id"]), str(fx["away_club_id"])])
	season.record.report.save_result(id, 3, 1, "", "", season.record.standings)
	season.record.standings.recompute()
	var row := season.record.fixtures.one(id)
	assert_eq(str(row["status"]), "played", "the fixture did not take its result")
	var home := _row(season, str(fx["home_club_id"]))
	var away := _row(season, str(fx["away_club_id"]))
	assert_eq(int(home["points"]), 3, "the winner was not paid three points")
	assert_eq(int(home["home_gf"]), 3, "the home goals did not move with the result")
	assert_eq(int(away["away_ga"]), 3, "the away goals against did not move")
	assert_eq(season.record.fixtures.played(), 1, "the ledger did not count the result")
	assert_eq(season.record.fixtures.unplayed(), 379, "the ledger lost a pending fixture")
	season.close()

func _row(season: LeagueSeason, club_id: String) -> Dictionary:
	for r in season.record.standings.table():
		if str(r["club_id"]) == club_id:
			return r
	return {}
