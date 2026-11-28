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
			"season_archive", "player_season_archive", "player_history", "player_contract",
			"club_finance", "club_ledger"]:
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


func test_a_loan_returns_to_the_parent_before_the_new_season() -> void:
	var season := _finished("Loan Rollover")
	var parent := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var loanee := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1 OFFSET 1;").get(
		"id", ""))
	var player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;", [parent]).get(
		"id", ""))
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	var proposed := MarketLoans.propose(season.save, parent, loanee, player, {
		"wage": wage, "wage_loanee": wage, "start_date": str(season.save.current_date()),
		"end_date": "2027-05-31"}, str(season.save.current_date()))
	assert_eq(str(MarketLoans.seal(str(proposed.get("loan", "")),
		str(season.save.current_date())).get("state", "")), MarketLoanRecords.ACTIVE,
		"the loan did not seal")
	assert_eq(str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player]).get("club_id", "")), loanee, "the loan did not move the player")
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	assert_eq(str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player]).get("club_id", "")), parent, "the loan did not return at the rollover")


func test_an_unserved_ban_carries_into_the_next_season() -> void:
	var season := _finished("Carried Ban")
	var row := PLDatabase.row(
		"SELECT p.id AS id, p.club_id AS club_id FROM player p "
		+ "JOIN player_contract c ON c.player_id = p.id "
		+ "WHERE c.status = 'active' AND c.end_date > '2029-06-30' AND p.age <= 23 "
		+ "ORDER BY p.id LIMIT 1;")
	assert_false(row.is_empty(), "the save has no young contracted player")
	var id := str(row["id"])
	var club := str(row["club_id"])
	SeasonAvailability.suspend(id, club, 2, "red", "2027-05-01")
	SeasonAvailability.injure(id, club, "2027-05-01", "knock", 5, 1.0)
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	var ban := PLDatabase.row(
		"SELECT matches_left, competition_id FROM league_absence WHERE player_id = ? "
		+ "AND kind = 'suspension';", [id])
	assert_false(ban.is_empty(), "the unserved ban was wiped at the season boundary")
	assert_eq(int(ban.get("matches_left", 0)), 2, "the carried ban lost its length")
	var injury := PLDatabase.row(
		"SELECT 1 AS n FROM league_absence WHERE player_id = ? AND kind = 'injury';", [id])
	assert_true(injury.is_empty(), "an old injury crossed the season boundary")


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


func test_the_season_end_pays_the_prize_and_the_windows_open() -> void:
	var season := _finished("Season Money")
	var champion := str(season.record.standings.table("PL")[0]["club_id"])
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused a finished season")
	var prize := PLDatabase.row(
		"SELECT amount, season_index FROM club_ledger WHERE kind = 'prize' AND club_id = ?;",
		[champion])
	assert_false(prize.is_empty(), "the champion was paid no prize money")
	assert_eq(int(prize.get("season_index", -1)), 0, "the prize was booked against another season")
	assert_eq(int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM club_ledger WHERE kind = 'prize' AND season_index = 0;").get("n", 0)),
		20, "the rollover did not pay the finished season's prize curve")
	var opening := str(season.save.current_date())
	var summer := MarketWindows.state(opening, "ENG")
	assert_true(bool(summer.get("open", false)), "season two opens outside its summer window")
	assert_eq(str(summer.get("season_label", "")), SECOND_LABEL,
		"the window still belongs to season one")
	assert_eq(str(summer.get("source", "")), "generated", "season two did not draw its own windows")
	var winter := MarketWindows.state("2028-01-15", "ENG")
	assert_true(bool(winter.get("open", false)), "season two has no winter window")
	assert_eq(str(winter.get("season_label", "")), SECOND_LABEL, "the winter sits in another season")
	var balances := PLDatabase.row(
		"SELECT COUNT(*) AS n, MIN(season_index) AS oldest FROM club_finance;")
	assert_eq(int(balances.get("n", 0)), 20, "the rollover left a club without an opening balance")
	assert_eq(int(balances.get("oldest", -1)), 1, "a balance did not roll to the new season")


func test_the_isolated_season_run_rolls_twice_and_repeats_itself() -> void:
	var script: Script = load("res://tools/market_sim/season.gd")
	var first: Dictionary = script.run({"seasons": "2", "seed": "7001", "name": "Isolated Run"})
	assert_true(bool(first.get("ok", false)), "the isolated run refused to roll over")
	var log: Array = first.get("log", [])
	assert_eq(log.size(), 2, "the isolated run did not roll twice")
	for entry in log:
		assert_true(bool((entry as Dictionary).get("settle_repeat_is_a_no_op", false)),
			"a repeated settle rewrote the save at season %d" % int(entry.get("season", -1)))
		assert_eq(int((entry as Dictionary).get("archived_clubs", 0)), 20,
			"an isolated season archived no table")
	var second: Dictionary = script.run({"seasons": "2", "seed": "7001", "name": "Isolated Run"})
	assert_true(bool(second.get("ok", false)), "the repeated run refused to roll over")
	assert_eq(JSON.stringify(second.get("log", [])), JSON.stringify(log),
		"a repeated isolated run changed its answer")


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
	assert_eq(season.record.fixtures.unplayed(), 380, "season two has no calendar to show")
	assert_eq(season.record.fixtures.played(), 0, "season two opens with played fixtures")
	var hub := season.state()
	assert_eq(int(hub.get("season_index", -1)), 1, "the hub still reads season one")
	assert_eq(str(hub.get("season_label", "")), SECOND_LABEL, "the hub lost season two's label")
	assert_eq(int(hub.get("total", 0)), 380, "the hub does not count season two's fixtures")


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


func test_season_two_fills_the_places_and_keeps_every_other_slot() -> void:
	var season := _finished("UEFA Places", false, ["PL"], true)
	var places := _finish_places(season)
	var shape := _shape_counts()
	var carried := _members("UCL", "LP", "ESP")
	assert_gte(carried.size(), 2, "the seed carries no Spanish Champions League entrants")
	var stub_iso := ""
	var stub_round := ""
	for row in PLDatabase.rows(
			"SELECT competition_id, role, member_id FROM competition_member "
			+ "WHERE member_kind = 'club' AND role NOT LIKE 'drop:%';"):
		var iso := LeagueUefa.association_of(str(row["member_id"]))
		if LeagueUefa.is_continental(str(row["competition_id"])) \
				and not ["ENG", "ESP", "GER", "ITA"].has(iso):
			stub_iso = iso
			stub_round = str(row["role"])
			break
	assert_true(stub_iso != "", "the seed carries no stub association")
	var stubs := _members("UCL", stub_round, stub_iso)
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
	assert_eq(_members("UCL", "LP", "ESP"), carried,
		"an association whose league is not active changed its entrants")
	var labelled := 0
	for row in LeagueEuropeEntries.entrants(season.save, "UCL"):
		if str(row["association"]) == "ESP" and str(row["source"]) == "CARRIED OVER":
			labelled += 1
	assert_eq(labelled, carried.size(), "the carried entrants are not labelled")
	assert_eq(_members("UCL", stub_round, stub_iso), stubs,
		"a stub association's entrants did not stay put")


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


func _cup_members(competition_id: String, role: String = "") -> Array:
	var out: Array = []
	var sql := ("SELECT member_id, role FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club'")
	var bindings: Array = [competition_id]
	if role != "":
		sql += " AND role = ?"
		bindings.append(role)
	for row in PLDatabase.rows(sql + " ORDER BY member_id;", bindings):
		out.append(str(row["member_id"]))
	return out


func _stub_ids(cup_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM club WHERE competition_id = ? AND stub = 1 ORDER BY id;", [cup_id]):
		out.append(str(row["id"]))
	return out


func test_season_two_pairs_the_shield_from_last_season() -> void:
	var season := _finished("Shield Pair", true, ["PL"], true)
	var places := _finish_places(season)
	var champion := str(places[0])
	var cup_winner := str(places[4])
	_pin_cup_final("FAC", cup_winner, str(places[5]))
	var stubs := _stub_ids("FAC")
	assert_gte(stubs.size(), 8, "the seed has no FA Cup stubs")
	var before := _cup_members("FAC", "R1")
	for stub in stubs:
		assert_true(before.has(stub), "season one lost stub %s" % stub)
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the shield rollover refused a finished season")
	assert_eq(_sorted(_cup_members("CS", "F")), _sorted([champion, cup_winner]),
		"the Community Shield is not last season's champion and cup winner")
	var reading := LeagueCupPools.reading(season.save, "CS")
	assert_eq(str((reading[champion] as Dictionary).get("source", "")), "PL 1ST",
		"the shield reading does not name the champion")
	assert_eq(str((reading[cup_winner] as Dictionary).get("source", "")), "FAC WINNER",
		"the shield reading does not name the cup winner")
	var after := _cup_members("FAC", "R1")
	for stub in stubs:
		assert_true(after.has(stub), "a followed stub left the FA Cup pool")
	assert_eq(_sorted(stubs), _sorted(_stub_ids("FAC")), "a stub id was reminted")


func test_the_supercup_page_names_its_field() -> void:
	var season := _finished("Shield Field", true, ["PL"], true)
	var places := _finish_places(season)
	var champion := str(places[0])
	var cup_winner := str(places[4])
	_pin_cup_final("FAC", cup_winner, str(places[5]))
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the shield rollover refused a finished season")
	var line := LeagueCupPools.field_line(season.save, "CS")
	assert_true(line.begins_with("FIELD"), "the supercup page carries no field line")
	assert_true(line.contains("PL 1ST"), "the field line does not name the champion's place")
	assert_true(line.contains("FAC WINNER"), "the field line does not name the cup winner")
	assert_eq(LeagueCupPools.field_line(season.save, "FAC"), "",
		"a main cup drew a supercup field line")
	var view := LeagueCupView.cup(season, "CS", "F")
	assert_eq(str(view.get("field", "")), line, "the cup view drops the field line")
	var items: Array = LeagueCupSheet.new().cup_layout(Vector2(1600.0, 900.0), view)
	var drawn := false
	for item in items:
		if str((item as Dictionary).get("kind", "")) == "field":
			drawn = str((item as Dictionary).get("label", "")).begins_with("FIELD")
	assert_true(drawn, "the cup layout does not draw the field line")


func test_a_double_or_missing_cup_sends_the_league_runner_up() -> void:
	var season := _finished("Shield Double", true)
	var places := _finish_places(season)
	var champion := str(places[0])
	var runner := str(places[1])
	_pin_cup_final("FAC", champion, str(places[3]))
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the double rollover refused a finished season")
	assert_eq(_sorted(_cup_members("CS", "F")), _sorted([champion, runner]),
		"a double did not send the league runner-up")
	var reading := LeagueCupPools.reading(season.save, "CS")
	assert_true(str((reading[runner] as Dictionary).get("source", "")).begins_with("DOUBLE"),
		"the double reading is silent")
	season = _finished("Shield Missing", true)
	places = _finish_places(season)
	champion = str(places[0])
	runner = str(places[1])
	result = SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the missing-cup rollover refused a finished season")
	assert_eq(_sorted(_cup_members("CS", "F")), _sorted([champion, runner]),
		"a missing cup winner did not send the next league place")
	reading = LeagueCupPools.reading(season.save, "CS")
	assert_true(str((reading[runner] as Dictionary).get("source", "")).contains("OFF"),
		"the missing-cup reading is silent")


func test_carabao_byes_follow_the_english_europe_list() -> void:
	var season := _finished("Carabao Byes", true, ["PL"], true)
	var places := _finish_places(season)
	_pin_cup_final("FAC", str(places[10]), str(places[11]))
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the Carabao rollover refused a finished season")
	var r3 := _cup_members("EFLC", "R3")
	assert_eq(r3.size(), 9, "the Carabao lost its nine late byes")
	var europe: Array = []
	for cid in ["UCL", "UEL", "UECL"]:
		for club in _members(cid, "LP", "ENG") + _members(cid, "POMP", "ENG"):
			if LeaguePyramid.competition_of(club) == "PL" and not europe.has(club):
				europe.append(club)
	for club in europe:
		assert_true(r3.has(club), "%s is in Europe but not a Carabao R3 bye" % club)
	var l2 := []
	for row in SeasonArchive.table(0, "L2"):
		l2.append(str(row["club_id"]))
	if l2.is_empty():
		assert_eq(_cup_members("EFLC", "PR").size(), 4, "the Carabao preliminary lost its four")
	else:
		var lowest := _sorted(l2.slice(maxi(0, l2.size() - 4), l2.size()))
		var still: Array = []
		for club in lowest:
			if LeaguePyramid.competition_of(club) == "L2":
				still.append(club)
		for club in still:
			assert_true(_cup_members("EFLC", "PR").has(club),
				"%s finished bottom of League Two but missed the preliminary" % club)


func test_spain_reuses_the_supercopa_four_in_the_copa() -> void:
	var season := _finished("Supercopa Four", true, ["LL"], false)
	var places: Array = []
	for row in season.record.standings.table("LL"):
		places.append(str(row["club_id"]))
	assert_eq(places.size(), 20, "La Liga did not finish")
	var winner := str(places[5])
	var runner := str(places[6])
	_pin_cup_final("CDR", winner, runner)
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the Spanish cup rollover refused a finished season")
	var four := _sorted([str(places[0]), str(places[1]), winner, runner])
	assert_eq(_sorted(_cup_members("SCE", "SF")), four, "the Supercopa four is wrong")
	assert_eq(_sorted(_cup_members("CDR", "R32")), four, "the Copa late four is not the Supercopa")
	var overlap := _finished("Supercopa Overlap", true, ["LL"], false)
	places = []
	for row in overlap.record.standings.table("LL"):
		places.append(str(row["club_id"]))
	_pin_cup_final("CDR", str(places[0]), str(places[1]))
	result = SeasonRollover.apply(overlap)
	assert_true(bool(result.get("ok", false)), "the overlap rollover refused a finished season")
	assert_eq(_cup_members("SCE", "SF").size(), 4, "an overlap did not fill the Supercopa four")
	assert_true(_cup_members("SCE", "SF").has(str(places[2])),
		"the next La Liga place did not fill a Supercopa overlap")


func test_germany_and_italy_pair_their_supercups() -> void:
	var germany := _finished("DFLS Pair", true, ["BL", "BL2"], false)
	var bl: Array = []
	for row in germany.record.standings.table("BL"):
		bl.append(str(row["club_id"]))
	_pin_cup_final("DFBP", str(bl[3]), str(bl[4]))
	var stubs := _stub_ids("DFBP")
	var result := SeasonRollover.apply(germany)
	assert_true(bool(result.get("ok", false)), "the German cup rollover refused a finished season")
	assert_eq(_sorted(_cup_members("DFLS", "F")), _sorted([str(bl[0]), str(bl[3])]),
		"the DFL-Supercup is not last season's champion and cup winner")
	for stub in stubs:
		assert_true(_cup_members("DFBP", "R1").has(stub), "a DFB-Pokal stub left its slot")
	var italy := _finished("SCI Pair", true, ["SA", "SB"], false)
	var sa: Array = []
	for row in italy.record.standings.table("SA"):
		sa.append(str(row["club_id"]))
	_pin_cup_final("CI", str(sa[4]), str(sa[5]))
	result = SeasonRollover.apply(italy)
	assert_true(bool(result.get("ok", false)), "the Italian cup rollover refused a finished season")
	assert_eq(_sorted(_cup_members("SCI", "F")), _sorted([str(sa[0]), str(sa[4])]),
		"the Supercoppa is not last season's champion and Coppa winner")
	assert_eq(_cup_members("CI", "R16").size(), 8, "the Coppa lost its eight seeds")
	for club in sa.slice(0, 8):
		assert_true(_cup_members("CI", "R16").has(club),
			"%s finished top eight but missed the Coppa round of 16" % club)
	assert_eq(_cup_members("CI", "PR").size(), 8, "the Coppa preliminary lost its eight")


func test_cups_off_leave_the_seeded_pools_alone() -> void:
	var season := _finished("Cups Off", false, ["PL"], false)
	var before := _sorted(_cup_members("CS", "F"))
	assert_eq(before.size(), 2, "the seed lost the Community Shield priors")
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "a cups-off rollover refused a finished season")
	assert_eq(_sorted(_cup_members("CS", "F")), before, "cups off rewrote the Shield priors")
	assert_true(LeagueCupPools.reading(season.save, "CS").is_empty(),
		"cups off still wrote a cup_pools reading")
	assert_true(LeagueCupPools.reading(null, "CS").is_empty(),
		"a null save invented a reading")
	assert_true(LeagueCupPools.rebuild(null, 0, {}, {}).get("ok", true) == false,
		"a null season rebuilt the pools")


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
