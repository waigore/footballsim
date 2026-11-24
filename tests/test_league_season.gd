extends GdToolsTest

## The season loop driven like a player drives it: set up a save, walk the
## calendar, watch one fixture, take the planner's suggestion, and finish on the
## podium. One generated season is shared across the tests so the full 380-fixture
## run stays inside the per-test budget.

const SAVE_DIR := "user://saves_test_season_issue58"
const CACHE_DIR := "user://cache_test_season_issue58"
const SEED := 2026

var season: LeagueSeason = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Loop Season", "generated", "fixture_days", SEED)

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_a_new_season_opens_on_the_first_matchday() -> void:
	assert_not_null(season, "the season was not created")
	var state := season.state()
	assert_eq(str(state["name"]), "Loop Season", "the season lost its name")
	assert_eq(int(state["total"]), 380, "the calendar is not a full season")
	assert_eq(int(state["played"]), 0, "a new season has played games")
	assert_eq(int(state["matchday"]), 1, "a new season does not start at gameweek one")
	assert_eq(state["table"].size(), 20, "the table does not list every club")
	assert_eq(season.plan().size(), 10, "the first matchday does not have ten games")
	assert_true(state["summary"].is_empty(), "an unplayed season reported a winner")
	assert_eq(str(state["date"]), "2026-08-15", "the clock does not start in August")

func test_continue_settles_the_autos_and_moves_the_clock() -> void:
	var before := season.state()
	var result := season.advance()
	assert_eq((result["played"] as Array).size(), 10, "the matchday was not auto-simmed")
	assert_eq((result["pending"] as Array).size(), 0, "an auto matchday left matches waiting")
	assert_false(bool(result["complete"]), "the season finished in August")
	var after := season.state()
	assert_eq(int(after["played"]), int(before["played"]) + 10, "the ledger lost a matchday")
	assert_true(str(after["date"]) > str(before["date"]), "the clock did not move")
	var reports: Array = result["played"]
	for report in reports:
		assert_true(bool(report["played"]), "an auto fixture is not marked played")
		assert_gte((report["events"] as Array).size(), 0, "a report has no event list")
		assert_eq((report["score"] as Array).size(), 2, "a report has no score")
	var points := 0
	for row in after["table"]:
		points += int(row["points"])
		assert_eq(int(row["played"]), 1, "the table did not count the first gameweek")
	assert_gte(points, 20, "the table paid no points")

func test_a_watch_holds_the_clock_until_the_match_is_played() -> void:
	var date := str(season.state()["date"])
	var fixtures := season.plan()
	assert_eq(fixtures.size(), 10, "the second matchday is short")
	var held := str(fixtures[0]["id"])
	assert_true(season.set_watch(held, true), "the planner did not take a watch flag")
	var result := season.advance()
	assert_eq((result["pending"] as Array).size(), 1, "the watched fixture did not block")
	assert_eq((result["played"] as Array).size(), 9, "the autos did not play around the watch")
	assert_eq(str((result["pending"] as Array)[0]["id"]), held, "another fixture was held")
	assert_eq(str(season.state()["date"]), date, "the clock ran past a watched fixture")
	var watch := season.start_watch(held)
	assert_eq(str(watch["fixture_id"]), held, "the watch did not take the fixture")
	var engine := MatchEngine.new(SEED, str(watch["home"]), str(watch["away"]))
	engine.score[0] = 2
	engine.score[1] = 1
	engine.phase = "full_time"
	var seen := [0]
	season.match_recorded.connect(func(_r): seen[0] += 1)
	LeagueSeason.engine_finished(engine)
	assert_eq(seen[0], 1, "the watched result did not signal the hub")
	var stored := season.report(held)
	assert_true(bool(stored["played"]), "the watched fixture stayed unplayed")
	assert_eq((stored["score"] as Array)[0], 2, "the watched score was not stored")
	assert_true(str(season.state()["date"]) > date, "the clock did not move after the watch")
	assert_eq(season.watching_fixture, "", "the season is still waiting for that watch")

func test_suggestions_start_after_five_rounds() -> void:
	while season.record.completed_matchdays() < 5:
		season.advance()
	assert_gte(season.record.completed_matchdays(), 5, "five rounds never completed")
	var ids := season.suggest()
	var top := {}
	for row in season.state()["table"]:
		if int(row["position"]) <= 6:
			top[str(row["club_id"])] = true
	assert_eq(top.size(), 6, "the table has no top six")
	for id in ids:
		var fx := season.record.fixture(str(id))
		assert_true(top.has(str(fx["home_club_id"])), "a suggested game is not a top-six clash")
		assert_true(top.has(str(fx["away_club_id"])), "a suggested game is not a top-six clash")
	var flagged := 0
	for fx in season.plan():
		if int(fx["suggested"]) == 1:
			flagged += 1
	assert_eq(flagged, ids.size(), "the suggestion flags were not stored")

func test_the_calendar_keeps_rolling_through_midwinter() -> void:
	# Later rounds are played in batches so no single test blows the per-test
	# budget: the season is one shared object across the suite.
	_play_until(14)
	assert_gte(season.record.completed_matchdays(), 14, "the season stalled before round 14")
	assert_eq(season.matches_remaining(), 380 - int(season.state()["played"]), "the ledger is short")

func test_a_second_watch_mid_season_records_and_rolls_on() -> void:
	_play_until(20)
	var fixtures := season.plan()
	assert_true(fixtures.size() > 0, "round 21 has no fixtures")
	var held := str(fixtures[fixtures.size() - 1]["id"])
	season.set_watch(held, true)
	var result := season.advance()
	assert_eq((result["pending"] as Array).size(), 1, "the second watch did not block")
	var watch := season.start_watch(held)
	var engine := MatchEngine.new(SEED + 1, str(watch["home"]), str(watch["away"]))
	engine.score[0] = 0
	engine.score[1] = 0
	LeagueSeason.engine_finished(engine)
	assert_true(bool(season.report(held)["played"]), "the second watch did not store")
	assert_eq((season.report(held)["score"] as Array)[1], 0, "the second watch lost its score")

func test_the_season_walks_to_a_complete_round_robin() -> void:
	var guard := 0
	while season.matches_remaining() > 0 and guard < 40:
		season.advance()
		guard += 1
	assert_eq(season.matches_remaining(), 0, "the season could not be finished")
	assert_eq(str(season.state()["status"]), "complete", "the season did not close")
	var table: Array = season.state()["table"]
	var played := 0
	for row in table:
		played += int(row["played"])
		assert_eq(int(row["played"]), 38, "%s did not play 38 games" % row["club_id"])
	assert_eq(played, 760, "the table does not hold two appearances per fixture")

func test_the_podium_reads_the_saved_rules() -> void:
	var summary: Dictionary = season.summary()
	assert_false(summary.is_empty(), "a finished season has no summary")
	assert_eq(str(summary["champion"]["club"]), str(season.state()["table"][0]["club_name"]), "the champion is not top")
	assert_eq(str(summary["runner_up"]["club"]), str(season.state()["table"][1]["club_name"]), "the runner-up is not second")
	assert_eq((summary["europe"] as Array).size(), 6, "the v1 European cut is not six")
	assert_eq((summary["relegated"] as Array).size(), 3, "the drop is not three clubs")
	assert_eq(int((summary["relegated"] as Array)[0]["position"]), 18, "the drop does not start at 18th")
	assert_gte((summary["top_scorers"] as Array).size(), 1, "the season has no scorers")
	var champion_points := int(summary["champion"]["points"])
	var second_points := int(summary["runner_up"]["points"])
	assert_gte(champion_points, second_points, "the champion is behind the runner-up")

func test_a_finished_season_reopens_on_the_podium() -> void:
	var slug := str(season.save.slug)
	season.close()
	var reopened := LeagueSeason.open(slug)
	assert_not_null(reopened, "the finished season did not reopen")
	assert_eq(str(reopened.state()["status"]), "complete", "the reopened season lost its status")
	assert_false(reopened.summary().is_empty(), "the reopened season lost its podium")
	assert_eq(reopened.advance()["complete"], true, "a finished season played on")
	season = reopened

func test_a_lonely_season_object_is_safe() -> void:
	var lonely := LeagueSeason.new()
	assert_true(lonely.state().is_empty(), "an unopened season reported state")
	assert_eq(lonely.plan().size(), 0, "an unopened season planned fixtures")
	assert_true(lonely.report("nope").is_empty(), "an unopened season produced a report")
	assert_true(lonely.summary().is_empty(), "an unopened season produced a podium")
	assert_true(lonely.start_watch("nope").is_empty(), "an unopened season started a watch")
	assert_eq(lonely.matches_remaining(), 0, "an unopened season has matches")
	assert_false(bool(lonely.advance().get("ok", false)), "an unopened season advanced")
	lonely.close()

func test_engine_finish_without_watching_is_a_no_op() -> void:
	var before := season.record.played()
	var engine := MatchEngine.new(SEED, "MUN", "MCI")
	engine.score[0] = 1
	engine.score[1] = 1
	LeagueSeason.engine_finished(engine)
	assert_eq(season.record.played(), before, "an unrelated match reached the season")
	assert_eq(season.watching_fixture, "", "the season is waiting for a match nobody started")

func test_an_unknown_date_falls_back_to_the_saved_gameweek() -> void:
	assert_eq(season._matchday_of("1999-01-01"), season.save.matchday(), "an empty day lost the gameweek")

func _play_until(rounds: int) -> void:
	var guard := 0
	while season.record.completed_matchdays() < rounds and guard < 40:
		season.advance()
		guard += 1

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		DirAccess.make_dir_recursive_absolute(folder)
		for name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
