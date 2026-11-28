extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_season_rollover_440")
var CACHE_DIR := TestScratch.dir("cache_season_rollover_440")
const SEED := 5150
const FIRST_LABEL := "2026-27"
const SECOND_LABEL := "2027-28"

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


func _track(season: LeagueSeason) -> LeagueSeason:
	open_seasons.append(season)
	return season


func _finished(name: String, cups: bool = false, comps: Array = ["PL"],
		uefa: bool = false) -> LeagueSeason:
	var season := _track(LeagueSeason.create(name, "generated", "fixture_days", SEED, comps, cups,
		[], uefa))
	assert_not_null(season, "%s was not created" % name)
	_mark_finished(season)
	SeasonSettle.apply(season)
	return season


func _mark_finished(season: LeagueSeason) -> void:
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


func _labels(season: LeagueSeason) -> Array:
	var out: Array = []
	for cid in season.save.actives:
		out.append(str(PLRepository.shared().competition(str(cid)).get("season_label", "")))
	return out


func test_a_new_save_lands_on_the_first_season() -> void:
	var season := _track(LeagueSeason.create("Season One", "generated", "fixture_days", SEED))
	assert_not_null(season, "the save was not created")
	assert_true(season.save.theme_ready(), "a new save is not a market save")
	assert_eq(season.save.season_index(), 0, "a new save did not open on season one")
	assert_eq(season.save.season_label(), FIRST_LABEL, "a new save lost the shipped label")
	assert_eq(int(str(season.save.meta.get("db_version", "0"))), LeagueSave.SCHEMA_VERSION,
		"a new save did not stamp the schema version")


func test_every_market_table_carries_a_season_index() -> void:
	var season := _track(LeagueSeason.create("Season Schema", "generated", "fixture_days", SEED))
	assert_not_null(season, "the save was not created")
	for table in ["league_fixture", "league_table", "league_player_stat", "cup_round", "cup_tie",
			"season_archive", "player_season_archive", "player_history"]:
		var columns := {}
		for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
			columns[str(row["name"])] = true
		assert_true(columns.has("season_index"), "%s has no season_index" % table)
	var row := PLDatabase.row(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'league_player_stat';")
	assert_true("PRIMARY KEY (player_id, competition_id, club_id)" in str(row.get("sql", "")),
		"a player line is still keyed by the player alone")


func test_building_the_summary_mutates_no_row() -> void:
	var season := _finished("Read Purity")
	var before := FileAccess.get_md5(season.save.path)
	var preview := LeagueSeasonSummary.build(season)
	assert_false(preview.is_empty(), "a finished season has no podium to build")
	var after := FileAccess.get_md5(season.save.path)
	assert_eq(after, before, "building the summary wrote to the save")
	SeasonSettle.apply(season)
	var settled := FileAccess.get_md5(season.save.path)
	LeagueSeasonSummary.build(season)
	assert_eq(FileAccess.get_md5(season.save.path), settled,
		"reading a settled summary wrote again")


func test_settling_twice_leaves_a_byte_identical_save() -> void:
	var season := _finished("Idempotent Settle", false, ["PL", "CH"])
	var first := SeasonSettle.apply(season)
	var settled := FileAccess.get_md5(season.save.path)
	var second := SeasonSettle.apply(season)
	assert_false(first.is_empty(), "the settle found nothing to close")
	assert_eq(FileAccess.get_md5(season.save.path), settled, "a second settle rewrote the save")
	assert_eq(JSON.stringify(second), JSON.stringify(first), "a second settle answered differently")


func test_retirement_is_a_priced_chance() -> void:
	assert_eq(SeasonAgeing.chance(34), 0.0, "a 34-year-old can retire")
	assert_almost_eq(SeasonAgeing.chance(35), 0.4, 0.001, "thirty-five starts below the stated rate")
	assert_almost_eq(SeasonAgeing.chance(37), 0.7, 0.001, "the rate does not step by fifteen")
	assert_eq(SeasonAgeing.chance(40), 1.0, "a 40-year-old can stay on")


func test_age_comes_from_the_date_of_birth() -> void:
	var season := _track(LeagueSeason.create("Ageing", "generated", "fixture_days", SEED))
	assert_not_null(season, "the ageing save was not created")
	PLDatabase.execute(
		"UPDATE player SET date_of_birth = '2000-01-15', age = 1 WHERE id = ("
		+ "SELECT id FROM player ORDER BY id LIMIT 1);")
	var id := str(PLDatabase.row("SELECT id FROM player ORDER BY id LIMIT 1;")["id"])
	SeasonAgeing.age_everyone("2027-07-01")
	var row := PLDatabase.row("SELECT age FROM player WHERE id = ?;", [id])
	assert_eq(int(row.get("age", 0)), 27, "a birth date of 2000 read as another age")


func test_the_rollover_starts_season_two_on_its_own_calendar() -> void:
	var season := _finished("Season Two")
	var champion := str(season.record.standings.table("PL")[0]["club_id"])
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	assert_eq(season.save.season_index(), 1, "the save did not move to season two")
	assert_eq(season.save.season_label(), SECOND_LABEL, "the label did not follow the index")
	assert_eq(_labels(season), [SECOND_LABEL], "a competition kept season one's label")
	assert_eq(season.save.status(), "in_progress", "season two did not open for business")
	assert_eq(season.record.fixtures.unplayed(), 380, "season two is not a full calendar")
	assert_true(str(season.save.current_date()) >= "2027-06-01",
		"season two's clock is still in season one")
	assert_eq(season.record.fixtures.played(), 0, "season two opens with played fixtures")
	var archived := SeasonArchive.table(0, "PL")
	assert_eq(archived.size(), 20, "season one's table was not archived")
	assert_eq(str(archived[0]["club_id"]), champion, "the archive lost season one's champion")
	assert_eq(int(archived[0]["position"]), 1, "the archive lost its order")
	assert_true(SeasonArchive.table(0, "").size() >= 20, "the archive holds no club rows")


func test_no_player_develops_across_the_rollover() -> void:
	var season := _finished("Static Cards")
	var ovr := {}
	for row in PLDatabase.rows("SELECT id, ovr FROM player;"):
		ovr[str(row["id"])] = int(row["ovr"])
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	var checked := 0
	for row in PLDatabase.rows("SELECT id, ovr FROM player;"):
		var id := str(row["id"])
		if not ovr.has(id):
			continue
		assert_eq(int(row["ovr"]), int(ovr[id]), "%s's card moved with age" % id)
		checked += 1
	assert_gt(checked, 1000, "the rollover barely kept a squad")


func test_retirement_empties_the_top_of_the_age_curve() -> void:
	var season := _finished("Retirement")
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	var old := PLDatabase.row("SELECT COUNT(*) AS n FROM player WHERE age >= 40;")
	assert_eq(int(old.get("n", 0)), 0, "a forty-year-old survived the rollover")
	var history := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_history WHERE season_index = 1 AND kind = 'retired';")
	assert_eq(int(history.get("n", 0)), int((result["aged"] as Dictionary).get("retired", 0)),
		"the retired players left no history")


func test_a_second_season_can_be_played_out() -> void:
	var season := _finished("Third Season")
	var first := SeasonRollover.apply(season)
	assert_true(bool(first.get("ok", false)), "season two did not start")
	_mark_finished(season)
	assert_eq(season.save.status(), "complete", "season two never completed")
	var second := SeasonRollover.apply(season)
	assert_true(bool(second.get("ok", false)), "season three did not start")
	assert_eq(season.save.season_index(), 2, "the save did not reach season three")
	assert_eq(season.save.season_label(), "2028-29", "the third label is wrong")
	assert_eq(SeasonArchive.table(1, "PL").size(), 20, "season two was not archived")
	assert_eq(SeasonArchive.table(2, "PL").size(), 0, "season three was archived before it played")
	assert_eq(int(SeasonArchive.table(1, "PL")[0]["position"]), 1, "season two's archive is unordered")


func test_the_cups_are_redrawn_for_the_new_season() -> void:
	var season := _finished("Cup Rollover", true)
	assert_true(LeagueCup.has_round("FAC", "R1"), "the first season drew no FA Cup")
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the cup rollover refused a finished season")
	assert_true(LeagueCup.has_round("FAC", "R1"), "season two drew no FA Cup")
	var round := PLDatabase.row(
		"SELECT * FROM cup_round WHERE competition_id = 'FAC' AND round_id = 'R1';")
	assert_eq(int(round.get("season_index", -1)), 1, "the new cup round is not season two's")
	var tie := PLDatabase.row("SELECT * FROM cup_tie WHERE competition_id = 'FAC';")
	assert_eq(int(tie.get("season_index", -1)), 1, "the new cup tie is not season two's")
	var fixture := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'FAC' AND stage = 'R1' "
		+ "ORDER BY id LIMIT 1;")
	assert_true(str(fixture.get("kickoff", "")).begins_with("2027-"),
		"the new FA Cup round is still on season one's date")
	assert_eq(int(fixture.get("season_index", -1)), 1, "the new cup fixture is not season two's")


func test_both_advance_paths_route_through_the_clock() -> void:
	var season := _track(LeagueSeason.create("Clock Seam", "generated", "fixture_days", SEED))
	assert_not_null(season, "the clock save was not created")
	var ticks := season.market_ticks
	season.advance()
	assert_gt(season.market_ticks, ticks, "CONTINUE skipped the market tick")
	assert_eq(season.market_date, season.save.current_date(), "the tick lost the clock's date")
	for fx in season.record.fixtures.pending_upto(season.save.current_date()):
		LeagueSeasonSim.fixture(season, fx)
	ticks = season.market_ticks
	season.roll_clock()
	assert_gt(season.market_ticks, ticks, "the silent clock skipped the market tick")
	assert_true(season.market_date > "2026-08-15", "the tick did not follow the clock")


func test_the_podium_offers_new_season_on_desktop_and_phone() -> void:
	var sheet := LeaguePodiumSheet.new()
	for vp in [Vector2(1600.0, 900.0), Vector2(913.0, 411.0)]:
		var items: Array = sheet.layout(vp, {"summary": {}})
		var found := {}
		for item in items:
			if str(item.get("id", "")) == "season:new":
				found = item
		assert_false(found.is_empty(), "no NEW SEASON door at %s" % vp)
		assert_true(bool(found.get("pinned", false)), "NEW SEASON is not pinned at %s" % vp)
		assert_gte(float((found["rect"] as Rect2).size.x), 96.0,
			"NEW SEASON is too narrow on a thumb at %s" % vp)
		assert_true((found["rect"] as Rect2).position.x > 24.0, "NEW SEASON covers BACK")


func test_the_new_season_door_rolls_over_and_lands_on_the_hub() -> void:
	var season := _finished("Door Season")
	var screen := FakeScreen.new(season)
	LeagueDoors.start_season(screen)
	assert_eq(season.save.season_index(), 1, "the door did not start season two")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "the door did not land on the hub")
	assert_eq(screen.nav.depth(), 0, "the door left season one's pages behind")


func test_an_old_save_refuses_to_open_and_writes_nothing() -> void:
	var season := _finished("Old Save")
	var path := season.save.path
	PLDatabase.execute("DELETE FROM save_meta WHERE key = 'season_index';")
	LeagueSave.close()
	var before := FileAccess.get_md5(path)
	var opened := LeagueSeason.open(season.save.slug)
	assert_true(opened == null, "a save without the market schema opened")
	assert_eq(LeagueSave.last_error, LeagueSave.NEW_SAVE_MESSAGE, "the refusal gave no reason")
	assert_eq(FileAccess.get_md5(path), before, "refusing the save wrote to it")
	assert_eq(PLDatabase.current_path(), "", "a refused save stayed open")


func test_an_unfinished_season_cannot_roll_over() -> void:
	var season := _track(LeagueSeason.create("Open Season", "generated", "fixture_days", SEED))
	assert_not_null(season, "the open save was not created")
	var before := FileAccess.get_md5(season.save.path)
	var result := SeasonRollover.apply(season)
	assert_false(bool(result.get("ok", true)), "an unplayed season rolled into the next")
	assert_eq(str(result.get("reason", "")), "season_open", "the refusal named no reason")
	assert_eq(season.save.season_index(), 0, "the refused rollover moved the season")
	assert_eq(FileAccess.get_md5(season.save.path), before, "the refused rollover wrote to the save")


func _members(competition_id: String, role: String, iso: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? AND role = ? "
			+ "AND member_kind = 'club';", [competition_id, role]):
		var club := str(row["member_id"])
		if LeagueUefa.association_of(club) == iso:
			out.append(club)
	out.sort()
	return out


func _shape_counts() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT competition_id, role, member_id FROM competition_member "
			+ "WHERE member_kind = 'club';"):
		var cid := str(row["competition_id"])
		var role := str(row["role"])
		if not LeagueUefa.is_continental(cid) or role.begins_with("drop:"):
			continue
		var key := "%s|%s|%s" % [cid, LeagueUefa.association_of(str(row["member_id"])), role]
		out[key] = int(out.get(key, 0)) + 1
	return out


func _sorted(values: Array) -> Array:
	var out := values.duplicate()
	out.sort()
	return out


func _pin_cup_final(competition_id: String, winner: String, loser: String) -> void:
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, home_club_id, "
		+ "away_club_id, winner_club_id, home_goals, away_goals) VALUES (?, 'F', 0, ?, ?, ?, 2, 0);",
		[competition_id, winner, loser, winner])


func _finish_places(season: LeagueSeason) -> Array:
	var places: Array = []
	for row in season.record.standings.table("PL"):
		places.append(str(row["club_id"]))
	return places


func test_season_two_fills_england_from_last_seasons_places() -> void:
	var season := _finished("UEFA Places", false, ["PL"], true)
	var places := _finish_places(season)
	var shape := _shape_counts()
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	assert_eq(places.size(), 20, "season one's table was not finished")
	assert_eq(_members("UCL", "LP", "ENG"), _sorted(places.slice(0, 5)),
		"the Champions League places are not last season's top five")
	assert_eq(_members("UEL", "LP", "ENG"), _sorted(places.slice(5, 8)),
		"the Europa League places are not places six to eight")
	assert_eq(_members("UECL", "POMP", "ENG"), _sorted([places[8]]),
		"a cup that did not run did not pass its place down the league table")
	assert_eq(_shape_counts(), shape, "the frozen access-list shape moved")


func test_a_cup_winner_takes_its_slot_and_a_taken_one_passes_down() -> void:
	var season := _finished("UEFA Cups", true, ["PL"], true)
	var places := _finish_places(season)
	var cup_winner := str(places[11])
	var league_cup_winner := str(places[1])
	_pin_cup_final("FAC", cup_winner, str(places[13]))
	_pin_cup_final("EFLC", league_cup_winner, str(places[14]))
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the cup rollover refused a finished season")
	assert_true(_members("UEL", "LP", "ENG").has(cup_winner),
		"the FA Cup winner is not in the Europa League")
	assert_eq(_members("UECL", "POMP", "ENG"), _sorted([places[7]]),
		"a League Cup winner already in Europe did not pass its place down")
	var reading := LeagueEuropeEntries.reading(season.save, "UEL")
	assert_eq(str((reading[cup_winner] as Dictionary).get("source", "")), "FA CUP WINNER",
		"the entrants reading does not name the cup winner")
	assert_true(LeagueEuropeEntries.summary(season.save, "UEL").contains("1 CUP WINNER"),
		"the hub summary does not count the cup winner")


func test_an_inactive_association_carries_its_entrants_over() -> void:
	var season := _finished("UEFA Carried", false, ["PL"], true)
	var before := _members("UCL", "LP", "ESP")
	assert_gte(before.size(), 2, "the seed carries no Spanish Champions League entrants")
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	assert_eq(_members("UCL", "LP", "ESP"), before,
		"an association whose league is not active changed its entrants")
	var labelled := 0
	for row in LeagueEuropeEntries.entrants(season.save, "UCL"):
		if str(row["association"]) == "ESP" and str(row["source"]) == "CARRIED OVER":
			labelled += 1
	assert_eq(labelled, before.size(), "the carried entrants are not labelled")


func test_stub_associations_keep_the_same_clubs_in_the_same_slots() -> void:
	var season := _finished("UEFA Stubs", false, ["PL"], true)
	var probe := ""
	var round_id := ""
	for row in PLDatabase.rows(
			"SELECT competition_id, role, member_id FROM competition_member "
			+ "WHERE member_kind = 'club' AND role NOT LIKE 'drop:%';"):
		var iso := LeagueUefa.association_of(str(row["member_id"]))
		if LeagueUefa.is_continental(str(row["competition_id"])) \
				and not ["ENG", "ESP", "GER", "ITA"].has(iso):
			probe = iso
			round_id = str(row["role"])
			break
	assert_true(probe != "", "the seed carries no stub association")
	var before := _members("UCL", round_id, probe)
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	assert_eq(_members("UCL", round_id, probe), before,
		"a stub association's entrants did not stay put")


class FakeScreen extends RefCounted:
	const MODE_HUB := LeagueScreen.MODE_HUB
	var season: LeagueSeason = null
	var mode := LeagueScreen.MODE_PODIUM
	var month := ""
	var report: Dictionary = {}
	var roundup: Array = []
	var nav := LeagueNavStack.new()
	var refreshes := 0

	func _init(owner: LeagueSeason) -> void:
		season = owner

	func refresh() -> void:
		refreshes += 1
