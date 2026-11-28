extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_cup_entries_506")
var CACHE_DIR := TestScratch.dir("cache_cup_entries_506")
const SEED := 4242

var open_seasons: Array = []


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
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		var hg := 3 if home < away else 1
		var ag := 1 if home < away else 3
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [hg, ag, str(row["id"])])
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
	var row := PLDatabase.row(
		"SELECT club_id FROM season_archive WHERE season_index = 0 "
		+ "AND competition_id = 'PL' AND position = ?;", [place])
	return str(row.get("club_id", ""))


func _champion() -> String:
	return _placed(1)


func _members(competition_id: String, role: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' AND role = ? ORDER BY member_id;",
			[competition_id, role]):
		out.append(str(row["member_id"]))
	return out


func _in_league(club_id: String, leagues: Array) -> bool:
	var club := PLRepository.shared().club(club_id)
	return leagues.has(str(club.get("competition_id", "")))


func _stub_of(cup_id: String) -> String:
	var row := PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = ? AND stub = 1 ORDER BY id LIMIT 1;",
		[cup_id])
	return str(row.get("id", ""))


func test_the_pools_rebuild_from_the_live_tiers() -> void:
	var season := _finished("Pools")
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the season did not roll over")
	assert_eq(_members("FAC", "R1").size(), 80, "the FA Cup first round is not 80 clubs")
	assert_eq(_members("FAC", "R3").size(), 44, "the FA Cup third round is not 44 clubs")
	assert_eq(_members("EFLC", "PR").size(), 4, "the Carabao preliminary is not four clubs")
	assert_eq(_members("EFLC", "R1").size(), 68, "the Carabao first round is not 68 clubs")
	assert_eq(_members("EFLC", "R2").size(), 11, "the Carabao second round is not 11 clubs")
	assert_eq(_members("EFLC", "R3").size(), 9, "the Carabao third round is not nine clubs")
	for club_id in _members("FAC", "R1"):
		var ok := _in_league(club_id, ["L1", "L2", "NL"]) \
			or str(PLRepository.shared().club(club_id).get("competition_id", "")) == "FAC"
		assert_true(ok, "%s entered the FA Cup first round from no tier" % club_id)
	for club_id in _members("FAC", "R3"):
		assert_true(_in_league(club_id, ["PL", "CH"]),
			"%s entered the FA Cup third round from no top tier" % club_id)
	season.close()


func test_the_carabao_byes_follow_the_league_places_when_europe_is_off() -> void:
	var season := _finished("Byes")
	SeasonRollover.apply(season)
	var late := _members("EFLC", "R3")
	var early := _members("EFLC", "R2")
	for i in range(9):
		assert_true(late.has(_placed(i + 1)),
			"the Carabao third round skipped the league's %d" % (i + 1))
	for i in range(11):
		assert_true(early.has(_placed(i + 10)),
			"the Carabao second round skipped the league's %d" % (i + 10))
	season.close()


func test_the_shield_names_last_seasons_champion_and_cup_winner() -> void:
	var season := _finished("Shield")
	var cup_winner := _placed(5)
	_crown("FAC", cup_winner, _placed(6))
	SeasonRollover.apply(season)
	var field := _members("CS", "F")
	assert_eq(field.size(), 2, "the Community Shield is not two clubs")
	assert_true(field.has(_champion()), "the Community Shield left the champion out")
	assert_true(field.has(cup_winner), "the Community Shield left the cup winner out")
	var note := LeagueCupEntries.note(season.save, "CS")
	assert_true(note.find("FA CUP WINNER") >= 0, "the shield does not name the cup winner")
	assert_true(note.find("PL 1ST") >= 0, "the shield does not name the champion's place")
	season.close()


func test_a_double_falls_back_to_the_league_runner_up() -> void:
	var season := _finished("Double")
	_crown("FAC", _champion(), _placed(7))
	SeasonRollover.apply(season)
	var field := _members("CS", "F")
	assert_true(field.has(_champion()), "the shield left the champion out")
	assert_true(field.has(_placed(2)), "a double did not fall back to the runner-up")
	assert_true(not field.has(_placed(7)), "a double still fielded the beaten finalist")
	var note := LeagueCupEntries.note(season.save, "CS")
	assert_true(note.find("WINNER IN") >= 0, "the shield does not read the double")
	season.close()


func test_a_missing_cup_winner_falls_back_to_the_next_place() -> void:
	var season := _finished("No Cup")
	SeasonRollover.apply(season)
	var field := _members("CS", "F")
	assert_true(field.has(_champion()), "the shield left the champion out")
	assert_true(field.has(_placed(2)), "a cup that never ran did not fall back")
	var note := LeagueCupEntries.note(season.save, "CS")
	assert_true(note.find("FA CUP OFF") >= 0, "the shield does not name the missing cup")
	season.close()


func test_a_stub_keeps_its_id_in_the_new_pool() -> void:
	var season := _finished("Stubs")
	var stub := _stub_of("FAC")
	assert_true(stub != "", "the seed carries no FA Cup stub")
	var before := _members("FAC", "R1")
	assert_true(before.has(stub), "the stub did not open in the FA Cup first round")
	SeasonRollover.apply(season)
	var after := _members("FAC", "R1")
	assert_true(after.has(stub), "the followed stub left the FA Cup first round")
	assert_eq(str(PLRepository.shared().club(stub).get("competition_id", "")), "FAC",
		"the stub's own competition moved")
	season.close()


func test_cups_that_are_off_write_nothing() -> void:
	var season := _finished("Cups Off", false)
	var before := _members("FAC", "R1")
	SeasonRollover.apply(season)
	assert_eq(_members("FAC", "R1"), before, "a save with the cups off rebuilt the pools")
	season.close()
