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
		["PL", "LL", "BL", "BL2", "SA"], true)
	assert_not_null(season, "the cup season was not created")
	assert_eq(LeagueCup.active_ids(season.save),
		["FAC", "EFLC", "CS", "CDR", "SCE", "DFBP", "DFLS", "CI", "SCI"],
		"a country's cups did not start")
	assert_eq(_ties("CDR", "PR"), 10, "the Copa preliminary round is not ten ties")
	assert_eq(_ties("SCE", "SF"), 2, "the Supercopa is not two semi-finals")
	assert_eq(_ties("DFBP", "R1"), 32, "the DFB-Pokal first round is not thirty-two ties")
	assert_eq(_ties("CS", "F"), 1, "the Community Shield is not one match")
	assert_eq(_ties("CI", "PR"), 4, "the Coppa preliminary round is not four ties")
	assert_eq(_ties("SCI", "F"), 1, "the Supercoppa is not one match")
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

func test_an_italian_season_crowns_the_coppa_and_the_supercoppa() -> void:
	var season := LeagueSeason.create("Italian Cups", "generated", "fixture_days", 481,
		["SA", "SB"], true)
	assert_not_null(season, "the Italian cup season was not created")
	var ties := {"PR": 4, "R1": 16, "R2": 8, "R16": 8, "QF": 4, "SF": 2, "F": 1}
	for round_id in ties:
		var legs: int = 2 if round_id == "SF" else 1
		var rows := PLDatabase.rows(
			"SELECT * FROM league_fixture WHERE competition_id = 'CI' AND stage = ? "
			+ "AND status = 'pending' ORDER BY id;", [round_id])
		assert_eq(rows.size(), int(ties[round_id]) * legs,
			"the Coppa %s did not install its fixtures" % round_id)
		for fx in rows:
			LeagueSeasonSim.fixture(season, fx)
		assert_true(LeagueCup.round_complete("CI", round_id),
			"the Coppa %s did not settle" % round_id)
	assert_true(LeagueCupState.winner("CI") != "", "the Coppa crowned no winner")
	var seeds := LeagueCup.entrants("CI", "R16")
	var r16 := PLDatabase.rows(
		"SELECT home_club_id, away_club_id FROM cup_tie WHERE competition_id = 'CI' "
		+ "AND round_id = 'R16';")
	var field := {}
	for tie in r16:
		field[str(tie["home_club_id"])] = true
		field[str(tie["away_club_id"])] = true
	for club_id in seeds:
		assert_true(field.has(club_id), "a seeded club missed the round of sixteen")
	var sci := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'SCI' AND status = 'pending' "
		+ "LIMIT 1;")
	assert_false(sci.is_empty(), "the Supercoppa has no fixture")
	assert_true(str(sci.get("kickoff", "")).begins_with("2027-01"),
		"the Supercoppa does not settle in January")
	LeagueSeasonSim.fixture(season, sci)
	assert_true(LeagueCupState.winner("SCI") != "", "the Supercoppa crowned no winner")
	var coppa := LeagueCupState.honours("CI")
	assert_eq(str((coppa.get("europe", {}) as Dictionary).get("competition", "")), "UEL",
		"the Coppa winner names no European slot")
	assert_true((LeagueCupState.honours("SCI").get("europe", {}) as Dictionary).is_empty(),
		"the Supercoppa should not earn Europe")
	var cups := LeagueSeasonSummary._cups(season)
	assert_eq(cups.size(), 2, "the podium does not name Italy's two cups")
	var cup_ids := []
	for cup in cups:
		cup_ids.append(str((cup as Dictionary).get("id", "")))
	assert_true(cup_ids.has("CI") and cup_ids.has("SCI"), "the podium lost an Italian cup")
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
