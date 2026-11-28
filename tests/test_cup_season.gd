extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_cup_season_455")
var CACHE_DIR := TestScratch.dir("cache_test_cup_season_455")

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_all() -> void:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	TestScratch.clear(SAVE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_every_shipped_country_runs_its_cups() -> void:
	var season := LeagueSeason.create("Europe Cups", "generated", "fixture_days", 77,
		["PL", "LL", "BL", "BL2"], true)
	assert_not_null(season, "the cup season was not created")
	assert_eq(LeagueCup.active_ids(season.save), ["FAC", "EFLC", "CS", "CDR", "SCE", "DFBP", "DFLS"],
		"a country's cups did not start")
	assert_eq(_ties("CDR", "PR"), 10, "the Copa preliminary round is not ten ties")
	assert_eq(_ties("SCE", "SF"), 2, "the Supercopa is not two semi-finals")
	assert_eq(_ties("DFBP", "R1"), 32, "the DFB-Pokal first round is not thirty-two ties")
	assert_eq(_ties("CS", "F"), 1, "the Community Shield is not one match")
	season.close()

func test_a_full_cup_season_reaches_every_final() -> void:
	var season := LeagueSeason.create("Cup Run", "generated", "fixture_days", 99, ["PL"], true)
	assert_not_null(season, "the cup season was not created")
	var guard := 0
	while season.save.status() != "complete" and guard < 900:
		season.advance()
		guard += 1
	assert_eq(season.save.status(), "complete", "the season never finished")
	for cid in ["FAC", "EFLC", "CS"]:
		assert_true(LeagueCupState.winner(str(cid)) != "", "%s crowned no winner" % cid)
		assert_eq(int(_unplayed(str(cid))), 0, "%s left a fixture pending" % cid)
		assert_true(LeagueCupState.bracket(str(cid)).size() >= 1, "%s kept no bracket" % cid)
	var fa := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'FAC' AND round_id = 'F';")
	assert_eq(int(fa["n"]), 1, "the FA Cup final is not one tie")
	var honour := LeagueCupState.honours("FAC")
	assert_true(str(honour.get("winner_name", "")) != "", "the FA Cup honours have no winner")
	assert_eq(str((honour.get("europe", {}) as Dictionary).get("competition", "")), "UEL",
		"the FA Cup winner names no European slot")
	var summary := season.summary()
	assert_eq((summary.get("cups", []) as Array).size(), 3, "the podium does not name three cups")
	season.close()

func _ties(competition_id: String, round_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	return int(row.get("n", 0))

func _unplayed(competition_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = ? AND status <> 'played';",
		[competition_id])
	return int(row.get("n", 0))
