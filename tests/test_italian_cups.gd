extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_italian_cups_480")
var CACHE_DIR := TestScratch.dir("cache_test_italian_cups_480")


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


func test_the_seed_carries_the_italian_pair() -> void:
	var ids: Array = []
	for row in PLRepository.shared().cups():
		ids.append(str(row["id"]))
	assert_true(ids.has("CI"), "the seed has no Coppa Italia")
	assert_true(ids.has("SCI"), "the seed has no Supercoppa Italiana")
	assert_eq(PLRepository.shared().competition_kind("CI"), "cup", "the Coppa is not a cup")
	assert_eq(PLRepository.shared().competition_kind("SCI"), "supercup", "the Supercoppa is not a supercup")
	assert_eq(LeagueCup.rounds("CI").size(), 7, "the Coppa Italia does not ship seven rounds")
	assert_eq(LeagueCup.next_round("CI", "SF"), "F", "the semi-finals do not lead to the final")
	assert_eq(int(LeagueCup.round_rule("CI", "SF").get("legs", 0)), 2,
		"the Coppa semi-finals are not two legs")
	assert_true(LeagueCup.countries().has("Italy"), "Italy does not offer domestic cups")


func test_the_round_of_sixteen_seeds_serie_a_top_eight() -> void:
	var seeded: Array = []
	for row in PLDatabase.rows(
			"SELECT club_id FROM table_row WHERE competition_id = 'SA' "
			+ "ORDER BY position LIMIT 8;"):
		seeded.append(str(row["club_id"]))
	assert_eq(seeded.size(), 8, "Serie A ships no table to seed from")
	seeded.sort()
	var entrants: Array = LeagueCup.entrants("CI", "R16")
	entrants.sort()
	assert_eq(entrants, seeded, "the round of 16 does not seed Serie A's top eight")
	var first_round: Array = LeagueCup.entrants("CI", "R1")
	assert_eq(first_round.size(), 28, "the Coppa first round entry pool drifted")
	for club_id in seeded:
		assert_false(first_round.has(str(club_id)), "a seeded club also enters the first round")


func test_the_preliminary_pairs_the_serie_b_tail_and_serie_c_stubs() -> void:
	var pool: Array = LeagueCup.entrants("CI", "PR")
	assert_eq(pool.size(), 8, "the Coppa preliminary is not eight clubs")
	var stubs := 0
	for club_id in pool:
		var row := PLDatabase.row(
			"SELECT c.stub, c.country FROM club c WHERE c.id = ?;", [str(club_id)])
		assert_false(row.is_empty(), "a preliminary entrant has no club row")
		if int(row.get("stub", 0)) == 1:
			stubs += 1
			assert_eq(str(row.get("country", "")), "ITA", "a Serie C stub is not Italian")
			continue
		var place := PLDatabase.row(
			"SELECT position FROM table_row WHERE competition_id = 'SB' AND club_id = ?;",
			[str(club_id)])
		assert_gte(int(place.get("position", 0)), 17,
			"a Serie B club above the tail entered the preliminary round")
	assert_eq(stubs, 4, "the preliminary needs four Serie C stubs")


func test_the_cups_start_beside_serie_a_and_serie_b() -> void:
	var season := _season("Italy Cups Start")
	assert_eq(LeagueCup.active_ids(season.save), ["CI", "SCI"], "an Italy save does not run its cups")
	assert_eq(_ties("CI", "PR"), 4, "the Coppa preliminary is not four ties")
	assert_eq(_ties("SCI", "F"), 1, "the Supercoppa is not one match")
	season.close()


func test_the_coppa_italia_runs_from_the_preliminary_to_the_final() -> void:
	var season := _season("Italy Cups Run")
	for round_id in ["PR", "R1", "R2", "R16", "QF", "SF", "F"]:
		_play_round(season, "CI", str(round_id))
	assert_eq(_ties("CI", "SF"), 2, "the Coppa semi-finals are not two ties")
	assert_true(LeagueCupState.winner("CI") != "", "the Coppa Italia never crowned a winner")
	assert_eq(int(_unplayed("CI")), 0, "the Coppa Italia left a fixture pending")
	assert_eq(LeagueCupState.bracket("CI").size(), 7, "the Coppa bracket lost a round")
	var honour := LeagueCupState.honours("CI")
	assert_true(str(honour.get("winner_name", "")) != "", "the Coppa honours name no winner")
	assert_eq(str((honour.get("europe", {}) as Dictionary).get("competition", "")), "UEL",
		"the Coppa winner names no European slot")
	season.close()


func test_the_supercoppa_settles_in_january() -> void:
	var season := _season("Italy Supercoppa")
	var fixture := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'SCI' LIMIT 1;")
	assert_false(fixture.is_empty(), "the Supercoppa has no fixture")
	assert_true(str(fixture.get("kickoff", "")).begins_with("2027-01"),
		"the Supercoppa does not play in January")
	LeagueSeasonSim.fixture(season, fixture)
	var tie := PLDatabase.row("SELECT * FROM cup_tie WHERE competition_id = 'SCI';")
	assert_true(str(tie.get("winner_club_id", "")) != "", "the Supercoppa never settled")
	var pair := [str(tie.get("home_club_id", "")), str(tie.get("away_club_id", ""))]
	pair.sort()
	assert_eq(pair, ["ITA-INT1", "ITA-NAP1"], "the Supercoppa pairing is not the double's reading")
	season.close()


func _season(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", 4800, ["SA", "SB"], true)
	assert_not_null(season, "the Italian cup season was not created: %s" % LeagueSave.last_error)
	return season


func _play_round(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	for row in PLDatabase.rows(
			"SELECT * FROM league_fixture WHERE competition_id = ? AND stage = ? "
			+ "ORDER BY id;", [competition_id, round_id]):
		LeagueSeasonSim.fixture(season, row)


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
