extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_cups_455")
var CACHE_DIR := TestScratch.dir("cache_test_cups_455")
const SEED := 4242

var season: LeagueSeason = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Cup Season", "generated", "fixture_days", SEED, ["PL"], true)

func after_all() -> void:
	if season != null:
		season.close()
	TestScratch.clear(SAVE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func test_the_cups_start_beside_the_league() -> void:
	assert_not_null(season, "the season was not created")
	assert_eq(LeagueCup.active_ids(season.save), ["FAC", "EFLC", "CS"],
		"a Premier League save does not run England's cups")
	for cid in ["FAC", "EFLC", "CS"]:
		assert_true(LeagueCup.has_round(str(cid), "R1" if cid == "FAC" else ("PR" if cid == "EFLC" else "F")),
			"%s did not draw its first round" % cid)
	var r1 := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'FAC' AND round_id = 'R1';")
	assert_eq(int(r1["n"]), 40, "the FA Cup first round is not forty ties")
	var fixtures := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = 'FAC' AND stage = 'R1';")
	assert_eq(int(fixtures["n"]), 40, "the FA Cup first round did not install its fixtures")
	var shield := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'CS';")
	assert_eq(int(shield["n"]), 1, "the Community Shield is not one match")
	var names := LeagueCupState.bracket("CS")
	assert_eq(names.size(), 1, "the Shield bracket is not one round")
	var tie: Dictionary = (names[0]["ties"] as Array)[0]
	assert_true(str(tie["home"]) != "" and str(tie["away"]) != "", "the Shield has no pairing")

func test_the_draw_is_deterministic() -> void:
	var first := _fa_pairs(season)
	var other := LeagueSeason.create("Cup Season Other", "generated", "fixture_days", SEED, ["PL"], true)
	assert_not_null(other, "the second season was not created")
	var second := _fa_pairs(other)
	other.close()
	season.save.ensure_open()
	PLRepository.shared().invalidate()
	assert_eq(second.size(), first.size(), "the same seed drew a different number of ties")
	for i in range(first.size()):
		assert_eq(str(second[i]), str(first[i]), "the same seed drew a different first-round tie")

func test_the_shield_settles_on_its_day() -> void:
	var shield := _fixture("CS", "F", 1)
	assert_false(shield.is_empty(), "the Shield fixture is missing")
	var date := str(shield["kickoff"])
	var guard := 0
	while LeagueCupState.winner("CS") == "" and guard < 12:
		season.advance()
		guard += 1
	assert_true(LeagueCupState.winner("CS") != "", "the Shield never settled")
	var tie := PLDatabase.row("SELECT * FROM cup_tie WHERE competition_id = 'CS';")
	assert_true(str(tie["winner_club_id"]) != "", "the Shield tie kept no winner")
	assert_true(int(tie["pens_home"]) >= 0 or int(tie["extra_time"]) == 1
		or int(tie["home_goals"]) != int(tie["away_goals"]),
		"a level Shield was left without penalties")
	assert_true(date <= str(season.save.current_date()), "the Shield settled after its date")

func test_round_one_winners_make_round_two() -> void:
	var rows := PLDatabase.rows(
		"SELECT * FROM league_fixture WHERE competition_id = 'FAC' AND stage = 'R1' ORDER BY id;")
	assert_eq(rows.size(), 40, "round one lost a tie")
	for fx in rows:
		LeagueSeasonSim.fixture(season, fx)
	var done := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'FAC' AND round_id = 'R1' "
		+ "AND winner_club_id <> '';")
	assert_eq(int(done["n"]), 40, "round one left a tie without a winner")
	assert_true(LeagueCup.has_round("FAC", "R2"), "round two was not drawn")
	var r2 := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'FAC' AND round_id = 'R2';")
	assert_eq(int(r2["n"]), 20, "round two is not twenty ties")
	var r3 := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'FAC' AND round_id = 'R3';")
	assert_eq(int(r3["n"]), 0, "round three was drawn before its entrants settled")

func test_a_two_legged_tie_settles_on_aggregate() -> void:
	var legs := PLDatabase.rows(
		"SELECT * FROM league_fixture WHERE competition_id = 'CDR' AND stage = 'PR' "
		+ "ORDER BY id LIMIT 2;")
	if legs.is_empty():
		var pr := LeagueCupState.draw_round(season, "CDR", "PR",
			LeagueCup.entrants("CDR", "PR"))
		assert_true(pr, "the Copa preliminary round was not drawn")
		legs = PLDatabase.rows(
			"SELECT * FROM league_fixture WHERE competition_id = 'CDR' AND stage = 'PR' "
			+ "ORDER BY id LIMIT 2;")
	assert_eq(legs.size(), 2, "the Copa preliminary round is not two legs")
	for fx in legs:
		LeagueSeasonSim.fixture(season, fx)
	var tie := PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = 'CDR' AND round_id = 'PR' ORDER BY tie_index LIMIT 1;")
	assert_true(str(tie["winner_club_id"]) != "", "the two-legged tie kept no winner")
	assert_eq(int(tie["home_goals"]) + int(tie["away_goals"]),
		_sum_legs(legs), "the tie's aggregate does not add up the two legs")

func test_cup_state_survives_a_reopen() -> void:
	var rounds := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_round WHERE competition_id = 'FAC';")
	var before := int(rounds["n"])
	var slug := season.save.slug
	season.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the cup save did not reopen")
	var after := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_round WHERE competition_id = 'FAC';")
	assert_eq(int(after["n"]), before, "the reopen lost a drawn round")
	assert_true(LeagueCupState.winner("CS") != "", "the reopen lost the Shield result")

func test_a_cup_fixture_is_not_watchable() -> void:
	var fx := _pending_cup_fixture()
	assert_false(fx.is_empty(), "no cup fixture is pending")
	assert_false(season.set_watch(str(fx["id"]), true), "a cup fixture took a watch flag")
	var row := PLDatabase.row("SELECT watched FROM league_fixture WHERE id = ?;", [str(fx["id"])])
	assert_eq(int(row.get("watched", 0)), 0, "a cup fixture kept a watch flag")

func test_a_cup_result_leaves_the_league_ledger_alone() -> void:
	var fx := _pending_cup_fixture()
	assert_false(fx.is_empty(), "no cup fixture is pending")
	var before := PLDatabase.row(
		"SELECT SUM(played) AS n FROM league_table WHERE competition_id = 'PL';")
	var apps := PLDatabase.row(
		"SELECT SUM(apps) AS n FROM league_player_stat WHERE competition_id = 'PL';")
	LeagueSeasonSim.fixture(season, fx)
	var after := PLDatabase.row(
		"SELECT SUM(played) AS n FROM league_table WHERE competition_id = 'PL';")
	var apps_after := PLDatabase.row(
		"SELECT SUM(apps) AS n FROM league_player_stat WHERE competition_id = 'PL';")
	assert_eq(int(after["n"]), int(before["n"]), "a cup tie moved the league table")
	assert_eq(int(apps_after["n"]), int(apps["n"]), "a cup tie wrote league player stats")

func _fa_pairs(owner: LeagueSeason) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT home_club_id, away_club_id FROM cup_tie WHERE competition_id = 'FAC' "
			+ "AND round_id = 'R1' ORDER BY tie_index;"):
		out.append("%s|%s" % [str(row["home_club_id"]), str(row["away_club_id"])])
	return out

func _pending_cup_fixture() -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM league_fixture WHERE stage <> '' AND status = 'pending' ORDER BY kickoff, id LIMIT 1;")

func _fixture(competition_id: String, stage: String, leg: int) -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = ? AND stage = ? AND leg = ? LIMIT 1;",
		[competition_id, stage, leg])

func _sum_legs(legs: Array) -> int:
	var total := 0
	for fx in legs:
		total += int(PLDatabase.row("SELECT home_goals + away_goals AS n FROM league_fixture WHERE id = ?;", [str(fx["id"])])["n"])
	return total
