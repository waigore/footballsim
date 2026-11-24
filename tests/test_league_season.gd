extends GdToolsTest

## The season loop driven like a player drives it: set up a save, walk the
## calendar, watch one fixture, take the planner's suggestion, and finish on the
## podium. One generated season is shared across the tests so the full 380-fixture
## run stays inside the per-test budget.

var SAVE_DIR := TestScratch.dir("saves_test_season_issue58")
var CACHE_DIR := TestScratch.dir("cache_test_season_issue58")
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
		assert_eq(int(row["home_played"]) + int(row["away_played"]), 1,
			"the side records did not count the first gameweek")
		assert_eq(int(row["home_gf"]) + int(row["away_gf"]), int(row["gf"]),
			"the side goals do not add up to the overall goals")
		assert_eq(int(row["home_ga"]) + int(row["away_ga"]), int(row["ga"]),
			"the side goals against do not add up")
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
	# #124: the day that was played stays current so the hub can show its result;
	# the next Continue moves the clock on.
	assert_eq(str(season.state()["date"]), date, "the clock ran off the day the watch was played")
	var on_day := false
	for fx in season.plan():
		if str(fx["id"]) == held:
			on_day = str(fx["status"]) == "played"
	assert_true(on_day, "the played fixture left its own day")
	season.advance()
	assert_true(str(season.state()["date"]) > date, "Continue did not move the clock on")
	assert_eq(season.watching_fixture, "", "the season is still waiting for that watch")

## #100: a watch the player walks out of is played out on the physical engine —
## both halves, no presentation — and lands on the save like full time does.
func test_leaving_a_watch_early_finishes_it_on_the_engine() -> void:
	var fixtures := season.plan()
	var held := str(fixtures[fixtures.size() - 1]["id"])
	season.set_watch(held, true)
	var blocked := season.advance()
	var pending: Array = blocked["pending"]
	assert_eq(pending.size(), 1, "the watch did not hold the clock")
	assert_true(int(pending[0]["watched"]) == 1, "the pending fixture is not a watch")
	assert_eq(str(pending[0]["id"]), held, "Continue would open another fixture")
	var watch := season.start_watch(held)
	assert_eq(str(watch["fixture_id"]), held, "the watch did not take the fixture")
	var engine := MatchEngine.new(SEED + 3, str(watch["home"]), str(watch["away"]))
	engine.half = 2
	engine.clock = 5390.0
	engine.added[1] = 0.0
	season.finishing = true
	assert_false(season.set_watch(held, false), "a finishing watch took a planner flag")
	assert_true(season.start_watch(held).is_empty(), "a finishing watch started a second match")
	assert_false(engine.run_to_full_time(0), "a zero budget played the rest out")
	assert_true(engine.run_to_full_time(), "the rest of the match was not played out")
	assert_eq(engine.phase, "full_time", "the engine never reached full time")
	PLSimStats.record_match(engine)
	var stored := season.report(held)
	assert_true(bool(stored["played"]), "the left-behind watch was not saved")
	assert_eq(int((stored["score"] as Array)[0]), int(engine.score[0]), "the saved score is not the engine's")
	assert_false(season.finishing, "the season still thinks it is finishing")
	assert_eq(season.watching_fixture, "", "the season still waits for that watch")

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
		assert_eq(int(row["home_played"]), 19, "%s did not play 19 at home" % row["club_id"])
		assert_eq(int(row["away_played"]), 19, "%s did not play 19 away" % row["club_id"])
		assert_eq(int(row["home_won"]) + int(row["away_won"]), int(row["won"]),
			"%s lost a win in the side split" % row["club_id"])
		assert_eq(int(row["home_drawn"]) + int(row["away_drawn"]), int(row["drawn"]),
			"%s lost a draw in the side split" % row["club_id"])
		assert_eq(int(row["home_lost"]) + int(row["away_lost"]), int(row["lost"]),
			"%s lost a defeat in the side split" % row["club_id"])
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

func test_the_encyclopedia_reads_the_live_table() -> void:
	var rows := PLRepository.shared().table()
	assert_eq(rows.size(), 20, "the repository table is short while a save is open")
	assert_eq(int(rows[0]["position"]), 1, "the live table has no positions")
	assert_true(rows[0].has("club_name"), "the live table lost its club labels")
	var mine := season.record.table()
	assert_eq(str(rows[0]["club_id"]), str(mine[0]["club_id"]), "the repository is not reading the save")

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

## The full table is only worth reading if its home and away splits are the
## fixture ledger itself.
func test_every_side_total_matches_the_fixture_ledger() -> void:
	var rows: Array = season.record.table()
	assert_eq(rows.size(), 20, "the table is short")
	var home := {}
	for row in PLDatabase.rows(
		"SELECT home_club_id AS club, COUNT(*) AS n, SUM(home_goals) AS gf, "
		+ "SUM(away_goals) AS ga FROM league_fixture WHERE status = 'played' "
		+ "GROUP BY home_club_id;"
	):
		home[str(row["club"])] = row
	assert_eq(home.size(), 20, "not every club has a home record")
	for row in rows:
		var club := str(row["club_id"])
		assert_true(home.has(club), "%s is missing from the fixture ledger" % club)
		var h: Dictionary = home[club]
		assert_eq(int(row["home_played"]), int(h["n"]), "%s lost home games" % club)
		assert_eq(int(row["home_gf"]), int(h["gf"]), "%s lost home goals" % club)
		assert_eq(int(row["home_ga"]), int(h["ga"]), "%s lost home goals against" % club)
		assert_eq(int(row["home_played"]) + int(row["away_played"]), int(row["played"]),
			"%s side games do not add up" % club)
		assert_eq(int(row["home_gf"]) + int(row["away_gf"]), int(row["gf"]),
			"%s side goals do not add up" % club)
		assert_eq(int(row["home_ga"]) + int(row["away_ga"]), int(row["ga"]),
			"%s side goals against do not add up" % club)

## An older save (or one whose side columns were never filled) gets its home and
## away totals rebuilt from the played fixtures when the season opens.
func test_opening_a_save_rebuilds_its_side_totals() -> void:
	var slug := str(season.save.slug)
	PLDatabase.execute(
		"UPDATE league_table SET home_played = 0, home_gf = 0, away_played = 0, "
		+ "away_gf = 0, away_ga = 0;")
	season.close()
	var reopened := LeagueSeason.open(slug)
	assert_not_null(reopened, "the save did not reopen")
	var rows: Array = reopened.record.table()
	assert_eq(int(rows[0]["home_played"]), 19, "opening the save did not rebuild the home record")
	var home := 0
	var goals := 0
	for row in rows:
		home += int(row["home_played"])
		goals += int(row["home_gf"]) + int(row["away_gf"])
	assert_eq(home, 380, "the rebuilt home records do not add up to the fixture ledger")
	var total := PLDatabase.row(
		"SELECT SUM(home_goals) + SUM(away_goals) AS n FROM league_fixture WHERE status = 'played';")
	assert_eq(goals, int(total["n"]), "the rebuilt side goals are not the fixture ledger")
	season = reopened

## Recompute is the repair path an older save takes: a row that drifted comes
## back to the ledger, home and away included.
func test_recompute_restores_a_drifted_side_record() -> void:
	var before: Array = season.record.table()
	var row: Dictionary = before[0]
	PLDatabase.execute(
		"UPDATE league_table SET home_gf = 999, away_played = 0, points = 0 "
		+ "WHERE club_id = ?;", [str(row["club_id"])])
	season.record.recompute_table()
	var found := {}
	for r in season.record.table():
		if str(r["club_id"]) == str(row["club_id"]):
			found = r
	assert_false(found.is_empty(), "the drifted club vanished from the table")
	assert_eq(int(found["home_gf"]), int(row["home_gf"]), "the recompute lost the home goals")
	assert_eq(int(found["away_played"]), int(row["away_played"]), "the recompute lost the away games")
	assert_eq(int(found["points"]), int(row["points"]), "the recompute lost the points")

func _play_until(rounds: int) -> void:
	var guard := 0
	while season.record.completed_matchdays() < rounds and guard < 40:
		season.advance()
		guard += 1

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
