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

func test_a_regional_round_pairs_every_club() -> void:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'EFLC' AND round_id = 'PR';")
	assert_eq(int(row["n"]), 2, "the regional preliminary round dropped a club")
	var clubs := PLDatabase.row(
		"SELECT COUNT(DISTINCT club_id) AS n FROM (SELECT home_club_id AS club_id "
		+ "FROM cup_tie WHERE competition_id = 'EFLC' AND round_id = 'PR' UNION "
		+ "SELECT away_club_id FROM cup_tie WHERE competition_id = 'EFLC' AND round_id = 'PR');")
	assert_eq(int(clubs["n"]), 4, "the regional sections did not pair four clubs")

func test_the_regional_sections_are_balanced_both_ways() -> void:
	var north: Array = ["n1"]
	var south: Array = ["s1", "s2"]
	LeagueCupDraw._balance(north, south)
	assert_eq(north.size(), 2, "an odd north section did not take a southern club")
	assert_eq(south.size(), 1, "the southern section kept its extra club")
	var north2: Array = ["n1", "n2"]
	var south2: Array = ["s1"]
	LeagueCupDraw._balance(north2, south2)
	assert_eq(south2.size(), 2, "an odd south section did not take a northern club")
	assert_eq(north2.size(), 1, "the northern section kept its extra club")

func test_the_shared_helpers_dedupe_and_install_a_round() -> void:
	assert_eq(LeagueCupDraw.unique(["a", "a", "", "b"]), ["a", "b"],
		"the shared draw pool kept blanks or duplicates")
	var rule := {"date": "2026-09-01", "second_leg": "2026-09-08", "legs": 2}
	LeagueCupTie.install_round("TST", "R1", 1, [{"home": "a", "away": "b"}], rule, "cup")
	var legs := PLDatabase.rows(
		"SELECT * FROM league_fixture WHERE competition_id = 'TST' ORDER BY leg;")
	assert_eq(legs.size(), 2, "a two-leg round did not install both legs")
	assert_eq(str(legs[0]["id"]), "cup-TST-R1-00-1", "the first-leg id drifted")
	assert_eq(str(legs[1]["id"]), "cup-TST-R1-00-2", "the second-leg id drifted")
	assert_eq(str(legs[1]["home_club_id"]), "b", "the second leg did not swap home")
	var tie := PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = 'TST' AND round_id = 'R1';")
	assert_eq(str(tie["home_club_id"]), "a", "the round did not keep its first tie")
	LeagueCupTie.install_round("TST", "R2", 2, [{"home": "a", "away": "b"}],
		{"date": "2026-09-01", "legs": 2}, "cup")
	var fallback := PLDatabase.row(
		"SELECT kickoff FROM league_fixture WHERE competition_id = 'TST' AND stage = 'R2' "
		+ "AND leg = 2;")
	assert_eq(str(fallback.get("kickoff", "")), "2026-09-08",
		"a missing second-leg date did not fall back a week")
	PLDatabase.execute("DELETE FROM league_fixture WHERE competition_id = 'TST';")
	PLDatabase.execute("DELETE FROM cup_tie WHERE competition_id = 'TST';")
	PLDatabase.execute("DELETE FROM cup_round WHERE competition_id = 'TST';")

func test_the_first_round_pairs_all_seventy_after_the_preliminary() -> void:
	var pr := PLDatabase.rows(
		"SELECT * FROM league_fixture WHERE competition_id = 'EFLC' AND stage = 'PR' ORDER BY id;")
	assert_eq(pr.size(), 2, "the Carabao preliminary round is not two ties")
	for fx in pr:
		LeagueSeasonSim.fixture(season, fx)
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'EFLC' AND round_id = 'R1';")
	assert_eq(int(row["n"]), 35, "the first round does not hold thirty-five ties")
	var clubs := PLDatabase.row(
		"SELECT COUNT(DISTINCT club_id) AS n FROM (SELECT home_club_id AS club_id "
		+ "FROM cup_tie WHERE competition_id = 'EFLC' AND round_id = 'R1' UNION "
		+ "SELECT away_club_id FROM cup_tie WHERE competition_id = 'EFLC' AND round_id = 'R1');")
	assert_eq(int(clubs["n"]), 70, "the first round did not pair seventy clubs")

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

func test_a_serie_a_save_runs_italys_cups() -> void:
	var italian := LeagueSeason.create("Italian Cups", "generated", "fixture_days", SEED, ["SA"], true)
	assert_not_null(italian, "the Serie A cup season was not created")
	assert_eq(LeagueCup.active_ids(italian.save), ["CI", "SCI"],
		"a Serie A save does not run Italy's cups")
	assert_true(LeagueCup.has_round("CI", "PR"), "the Coppa did not draw its preliminary round")
	var pr := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'CI' AND round_id = 'PR';")
	assert_eq(int(pr["n"]), 4, "the Coppa preliminary round is not four ties")
	var sci := PLDatabase.row("SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = 'SCI';")
	assert_eq(int(sci["n"]), 1, "the Supercoppa is not one match")
	var seeds := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM competition_member WHERE competition_id = 'CI' "
		+ "AND role = 'R16';")
	assert_eq(int(seeds["n"]), 8, "the Coppa round of sixteen is not eight seeded clubs")
	italian.close()
	season.save.ensure_open()
	PLRepository.shared().invalidate()

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

func test_a_cup_fixture_takes_a_watch_flag() -> void:
	var fx := _pending_cup_fixture()
	assert_false(fx.is_empty(), "no cup fixture is pending")
	assert_true(season.set_watch(str(fx["id"]), true), "a cup fixture refused a watch flag")
	var row := PLDatabase.row("SELECT watched FROM league_fixture WHERE id = ?;", [str(fx["id"])])
	assert_eq(int(row.get("watched", 0)), 1, "a cup fixture dropped its watch flag")
	assert_true(season.set_watch(str(fx["id"]), false), "a cup watch could not be cleared")


func test_a_watched_cup_tie_settles_through_the_engine() -> void:
	var shared_slug := season.save.slug
	var run := LeagueSeason.create("Watched Cup", "generated", "fixture_days", SEED + 41,
		["PL"], true)
	assert_not_null(run, "the watched-cup season could not be created")
	var fx := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'CS' AND stage = 'F' "
		+ "AND status = 'pending' LIMIT 1;")
	assert_false(fx.is_empty(), "the Shield fixture is missing")
	var fixture_id := str(fx["id"])
	var before := PLDatabase.row(
		"SELECT SUM(played) AS n FROM league_table WHERE competition_id = 'PL';")
	assert_true(run.set_watch(fixture_id, true), "the cup watch was refused")
	var watch := run.start_watch(fixture_id)
	assert_eq(str(watch.get("fixture_id", "")), fixture_id, "the cup watch did not open")
	var engine := MatchEngine.new(SEED + 11, str(watch["home"]), str(watch["away"]))
	engine.score[0] = 1
	engine.score[1] = 1
	engine.phase = "full_time"
	run.record_engine(engine)
	var stored := run.report(fixture_id)
	assert_true(bool(stored.get("played", false)), "the watched cup tie stayed unplayed")
	assert_true(LeagueCupState.winner("CS") != "", "the watched Shield kept no winner")
	var after := PLDatabase.row(
		"SELECT SUM(played) AS n FROM league_table WHERE competition_id = 'PL';")
	assert_eq(int(after["n"]), int(before["n"]), "a watched cup tie moved the league table")
	assert_true(LeagueCupTie.record_engine(run, {}, 0, 0).is_empty(),
		"an unknown cup fixture claimed a result")
	var rows := PLDatabase.rows(
		"SELECT * FROM league_fixture WHERE competition_id = 'FAC' AND stage = 'R1' "
		+ "AND status = 'pending' ORDER BY id LIMIT 2;")
	assert_gte(rows.size(), 2, "FA Cup first round lost its pending ties")
	var fa: Dictionary = rows[0]
	var flipped := fa.duplicate()
	flipped["home_club_id"] = str(fa["away_club_id"])
	flipped["away_club_id"] = str(fa["home_club_id"])
	var away_side := LeagueCupTie.record_engine(run, flipped, 2, 0)
	assert_true(str(away_side.get("winner", "")) != "",
		"an away-legged watch did not crown a winner")
	var level := LeagueCupTie.record_engine(run, rows[1], 0, 0)
	assert_true(bool(level.get("extra_time", false)) or int((level.get("pens", Vector2i(-1, -1)) as Vector2i).x) >= 0,
		"a level FA Cup watch skipped extra time and penalties")
	assert_true(str(level.get("winner", "")) != "", "a level FA Cup watch crowned no winner")
	var league_fx := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE stage = '' AND status = 'pending' "
		+ "ORDER BY kickoff, id LIMIT 1;")
	assert_false(league_fx.is_empty(), "no league fixture is pending")
	assert_true(run.set_watch(str(league_fx["id"]), true), "a league watch was refused")
	var league_watch := run.start_watch(str(league_fx["id"]))
	var league_engine := MatchEngine.new(SEED + 13, str(league_watch["home"]),
		str(league_watch["away"]))
	league_engine.score[0] = 1
	league_engine.score[1] = 0
	league_engine.phase = "full_time"
	run.record_engine(league_engine)
	assert_true(bool(run.report(str(league_fx["id"])).get("played", false)),
		"a watched league fixture stayed unplayed")
	run.close()
	season = LeagueSeason.open(shared_slug)
	assert_not_null(season, "the shared cup season did not reopen")

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
