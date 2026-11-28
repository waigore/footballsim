extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_cup_entries_506")
var CACHE_DIR := TestScratch.dir("cache_cup_entries_506")
const SEED := 4242

var open_seasons: Array = []

var current: LeagueSeason


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	for season in open_seasons:
		(season as LeagueSeason).close()
	open_seasons.clear()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _finished(name: String, cups: bool = true) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"], cups)
	assert_not_null(season, "%s was not created" % name)
	open_seasons.append(season)
	current = season
	PLDatabase.execute(
		"UPDATE league_fixture SET status = 'played', "
		+ "home_goals = CASE WHEN home_club_id < away_club_id THEN 3 ELSE 1 END, "
		+ "away_goals = CASE WHEN home_club_id < away_club_id THEN 1 ELSE 3 END;")
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	SeasonSettle.apply(season)
	return season


func _crown(cup_id: String, winner: String, loser: String) -> void:
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, home_club_id, "
		+ "away_club_id, winner_club_id, home_goals, away_goals) "
		+ "VALUES (?, 'F', 0, ?, ?, ?, 2, 1);", [cup_id, winner, loser, winner])


func _placed(place: int) -> String:
	for row in current.record.standings.table("PL"):
		if int(row.get("position", 0)) == place:
			return str(row.get("club_id", ""))
	return ""


func _members(competition_id: String, role: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' AND role = ? ORDER BY member_id;",
			[competition_id, role]):
		out.append(str(row["member_id"]))
	return out


func _in_league(club_id: String, leagues: Array) -> bool:
	return leagues.has(str(PLRepository.shared().club(club_id).get("competition_id", "")))


func _stub_of(cup_id: String) -> String:
	var row := PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = ? AND stub = 1 ORDER BY id LIMIT 1;",
		[cup_id])
	return str(row.get("id", ""))


func _ctx(places: Array, cups: Dictionary) -> Dictionary:
	return {"places": {"PL": places}, "ranked": {"PL": places}, "rank": {},
		"names": {"PL": "PREMIER LEAGUE"}, "europe": [],
		"stubs": {}, "cups": cups}


func test_the_rollover_rebuilds_the_pools_and_names_the_shield() -> void:
	var season := _finished("Rollover")
	var champion := _placed(1)
	var cup_winner := _placed(5)
	_crown("FAC", cup_winner, _placed(6))
	var stub := _stub_of("FAC")
	var top: Array = []
	for i in range(9):
		top.append(_placed(i + 1))
	SeasonRollover.apply(season)
	assert_eq(_members("FAC", "R1").size(), 80, "the FA Cup first round is not 80 clubs")
	assert_eq(_members("FAC", "R3").size(), 44, "the FA Cup third round is not 44 clubs")
	assert_eq(_members("EFLC", "PR").size(), 4, "the Carabao preliminary is not four clubs")
	assert_eq(_members("EFLC", "R1").size(), 68, "the Carabao first round is not 68 clubs")
	assert_eq(_members("EFLC", "R2").size(), 11, "the Carabao second round is not 11 clubs")
	assert_eq(_members("EFLC", "R3").size(), 9, "the Carabao third round is not nine clubs")
	for club_id in _members("FAC", "R1"):
		assert_true(_in_league(club_id, ["L1", "L2", "NL"]) or str(
			PLRepository.shared().club(club_id).get("competition_id", "")) == "FAC",
			"%s entered the FA Cup first round from no tier" % club_id)
	for club_id in _members("FAC", "R3"):
		assert_true(_in_league(club_id, ["PL", "CH"]),
			"%s entered the FA Cup third round from no top tier" % club_id)
	for i in range(9):
		assert_true(_members("EFLC", "R3").has(top[i]),
			"the Carabao third round skipped the league's %d" % (i + 1))
	var shield := _members("CS", "F")
	assert_eq(shield.size(), 2, "the Community Shield is not two clubs")
	assert_true(shield.has(champion), "the Community Shield left the champion out")
	assert_true(shield.has(cup_winner), "the Community Shield left the cup winner out")
	var note := LeagueCupEntries.note(season.save, "CS")
	assert_true(note.find("FA CUP WINNER") >= 0, "the shield does not name the cup winner")
	assert_true(note.find("1ST") >= 0, "the shield does not name the champion's place")
	assert_true(_members("FAC", "R1").has(stub), "the followed stub left the FA Cup first round")
	assert_eq(str(PLRepository.shared().club(stub).get("competition_id", "")), "FAC",
		"the stub's own competition moved")
	var view := LeagueCupView.cup(season, "CS", "F")
	assert_true(LeagueCupSheet.entry_note(view).begins_with("FIELD"),
		"the shield page carries no field line")
	var items: Array = LeagueCupSheet.new().cup_layout(Vector2(1600, 900), view)
	var drawn := false
	for item in items:
		if str((item as Dictionary).get("label", "")).begins_with("FIELD"):
			drawn = true
	assert_true(drawn, "the cup layout does not draw the field line")
	season.close()


func test_a_double_sends_the_league_runner_up() -> void:
	var ctx := _ctx(["ARS", "AVL", "BHA"], {"FAC": {"winner": "ARS", "runner_up": "MCI"}})
	var field := LeagueCupPairings.field("CS", ctx)
	assert_eq(field["rounds"].get("F", []), ["ARS", "AVL"],
		"a double did not fall back to the runner-up")
	assert_true(str(field["labels"]["AVL"]["source"]).find("WINNER IN") >= 0,
		"the double is not named on the reading")
	assert_eq(str(field["labels"]["ARS"]["source"]), "PREMIER LEAGUE 1ST",
		"the champion's place is not named")


func test_a_missing_cup_winner_falls_back_to_the_next_place() -> void:
	var ctx := _ctx(["ARS", "AVL", "BHA"], {})
	var field := LeagueCupPairings.field("CS", ctx)
	assert_eq(field["rounds"].get("F", []), ["ARS", "AVL"],
		"a cup that never ran did not fall back")
	assert_true(str(field["labels"]["AVL"]["source"]).find("FA CUP OFF") >= 0,
		"the missing cup is not named on the reading")
	assert_eq(str(field["labels"]["ARS"]["kind"]), "place", "the champion's source is not a place")


func test_cups_that_are_off_write_nothing() -> void:
	var season := _finished("Cups Off", false)
	var before := _members("FAC", "R1")
	var result := LeagueCupEntries.regenerate(season, 0, {})
	assert_true(not bool(result.get("ok", true)), "a save with the cups off rebuilt the pools")
	assert_eq(_members("FAC", "R1"), before, "a save with the cups off rewrote the pool")
	season.close()
