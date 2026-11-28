extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_availability")
var CACHE_DIR := TestScratch.dir("cache_test_availability")
const SEED := 4242

var season: LeagueSeason = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Availability Season", "generated", "fixture_days", SEED)

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func before_each() -> void:
	_wipe()

func _wipe() -> void:
	PLDatabase.execute("DELETE FROM league_absence;")
	PLDatabase.execute("DELETE FROM league_discipline;")
	PLDatabase.execute("DELETE FROM league_player_stat;")

func _first_club() -> String:
	return str(TeamData.team_ids()[0])

func _first_player(club_id: String) -> Dictionary:
	var team := TeamData.get_team(club_id)
	return team["starters"][0]


func test_a_roll_grades_the_injury_and_hides_the_days() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var grades := {}
	for i in range(200):
		var drawn := SeasonAvailability.roll(rng)
		var grade := str(drawn["grade"])
		var days := int(drawn["days"])
		assert_true(SeasonAvailability.GRADE_DAYS.has(grade), "an unknown grade was drawn")
		var span: Array = SeasonAvailability.GRADE_DAYS[grade]
		assert_gte(days, int(span[0]), "the days are under the grade's floor")
		assert_lte(days, int(span[1]), "the days are over the grade's ceiling")
		assert_gte(float(drawn["rate"]), SeasonAvailability.RATE_MIN, "the recovery rate left its band")
		assert_lte(float(drawn["rate"]), SeasonAvailability.RATE_MAX, "the recovery rate left its band")
		grades[grade] = int(grades.get(grade, 0)) + 1
	assert_true(grades.has("knock"), "no knock was ever drawn")
	assert_true(grades.has("muscle"), "no muscle injury was ever drawn")

func test_public_wording_reads_weeks_or_months_never_days() -> void:
	assert_eq(SeasonAvailability.recovery_label(0), "FIT", "a fit player reads as out")
	assert_eq(SeasonAvailability.recovery_label(5), "1 WEEK", "a knock does not read as a week")
	assert_eq(SeasonAvailability.recovery_label(14), "2 WEEKS", "a fortnight does not read as two weeks")
	assert_eq(SeasonAvailability.recovery_label(45), "7 WEEKS", "a month and a half does not read in weeks")
	assert_eq(SeasonAvailability.recovery_label(120), "4 MONTHS", "a long term does not read in months")
	assert_eq(SeasonAvailability.ban_label(1), "1 MATCH", "one match reads wrong")
	assert_eq(SeasonAvailability.ban_label(3), "3 MATCHES", "three matches read wrong")

func test_an_injury_persists_in_the_save_and_is_unavailable() -> void:
	var club := _first_club()
	var player := _first_player(club)
	var id := str(player["id"])
	assert_true(SeasonAvailability.injure(id, club, "2026-08-15", "muscle", 21, 1.0),
		"the injury did not land")
	assert_true(SeasonAvailability.unavailable(club).has(id), "the injured player is still selectable")
	var rows := SeasonAvailability.rows(club)
	var found := {}
	for row in rows:
		if str(row["player_id"]) == id:
			found = row
	assert_false(found.is_empty(), "the injury is not in the save")
	assert_eq(str(found["kind"]), "injury", "the row is not an injury")
	assert_eq(int(found["days_left"]), 21, "the hidden day count moved")
	assert_eq(str(found["due_on"]), "2026-09-05", "the hidden return date is wrong")
	var absences := SeasonAvailability.absences(club)
	assert_eq(absences.size(), 1, "the briefing does not list the absence")
	assert_eq(str((absences[0] as Dictionary)["label"]), "3 WEEKS", "the briefing leaked the days")

func test_a_month_tick_heals_by_the_days_that_passed() -> void:
	var club := _first_club()
	var player := _first_player(club)
	var id := str(player["id"])
	SeasonAvailability.injure(id, club, "2026-08-15", "ligament", 60, 1.0)

	assert_eq(SeasonAvailability.month_tick("2026-08-15", "2026-08-31"), 0,
		"a mid-month move healed a body")
	assert_eq(int(SeasonAvailability.rows(club)[0]["days_left"]), 60, "a mid-month move moved the days")

	SeasonAvailability.month_tick("2026-08-31", "2026-09-30")
	assert_eq(int(SeasonAvailability.rows(club)[0]["days_left"]), 30,
		"the month tick did not take the elapsed days")

	SeasonAvailability.injure(id, club, "2026-10-01", "knock", 6, 1.0)
	SeasonAvailability.month_tick("2026-10-31", "2026-11-30")
	assert_eq(SeasonAvailability.rows(club).size(), 0, "a healed body stayed out")

func test_the_recovery_rate_bends_the_month_without_jumping() -> void:
	var club := _first_club()
	var player := _first_player(club)
	var id := str(player["id"])
	SeasonAvailability.injure(id, club, "2026-08-15", "ligament", 84, 1.2)
	SeasonAvailability.month_tick("2026-08-31", "2026-09-30")
	assert_eq(int(SeasonAvailability.rows(club)[0]["days_left"]), 48,
		"a fast healer did not take the extra days")
	SeasonAvailability.injure(id, club, "2026-09-30", "ligament", 84, 0.8)
	SeasonAvailability.month_tick("2026-09-30", "2026-10-31")
	assert_eq(int(SeasonAvailability.rows(club)[0]["days_left"]), 59,
		"a slow healer healed as fast as the calendar")


func _book(club: String, player_id: String, yellow: int, red: int, matchday: int,
		competition_id: String = "") -> void:
	season.record.report.add_player_lines([{
		"player_id": player_id, "club_id": club, "competition_id": competition_id,
		"line": {"apps": 1, "goals": 0, "assists": 0, "yellow": yellow, "red": red},
	}])
	SeasonAvailability.apply_fixture(matchday, "2026-08-15", [{
		"club_id": club,
		"rows": [{"player_id": player_id, "yellow": yellow, "red": red}],
		"events": [],
	}], SEED, competition_id)

func test_five_yellows_ban_one_match_and_the_ban_is_served() -> void:
	var club := _first_club()
	var id := str(_first_player(club)["id"])
	for i in range(4):
		_book(club, id, 1, 0, 1)
	assert_eq(SeasonAvailability.absences(club).size(), 0, "four yellows banned a player")
	_book(club, id, 1, 0, 1)
	var absences := SeasonAvailability.absences(club)
	assert_eq(absences.size(), 1, "five yellows did not ban the player")
	assert_eq(str((absences[0] as Dictionary)["kind"]), "suspension", "the ban is not a suspension")
	assert_eq(str((absences[0] as Dictionary)["label"]), "1 MATCH", "the ban length is wrong")

	SeasonAvailability.apply_fixture(2, "2026-08-22", [{"club_id": club, "rows": [], "events": []}], SEED)
	assert_eq(SeasonAvailability.absences(club).size(), 0, "the ban was not served")

	_book(club, id, 1, 0, 2)
	assert_eq(SeasonAvailability.absences(club).size(), 0, "five cards paid twice")

func test_ten_yellows_ban_two_matches() -> void:
	var club := _first_club()
	var id := str(TeamData.get_team(club)["starters"][1]["id"])
	for i in range(10):
		_book(club, id, 1, 0, mini(i + 1, 20))
	var absences := SeasonAvailability.absences(club)
	assert_eq(absences.size(), 1, "ten yellows did not ban the player")
	assert_eq(str((absences[0] as Dictionary)["label"]), "2 MATCHES", "the second threshold is wrong")
	SeasonAvailability.apply_fixture(21, "2026-09-01", [{"club_id": club, "rows": [], "events": []}], SEED)
	assert_eq(str((SeasonAvailability.absences(club)[0] as Dictionary)["label"]), "1 MATCH",
		"the second match of the ban was not served")

func test_a_straight_red_and_a_second_yellow_both_ban_one_match() -> void:
	var home := str(TeamData.team_ids()[0])
	var away := str(TeamData.team_ids()[1])
	var sent_off := str(TeamData.get_team(home)["starters"][2]["id"])
	var two_yellows := str(TeamData.get_team(away)["starters"][3]["id"])
	_book(home, sent_off, 0, 1, 1)
	_book(away, two_yellows, 2, 0, 1)
	var kinds := {}
	for row in SeasonAvailability.rows(home):
		kinds[str(row["player_id"])] = str(row["grade"])
	assert_eq(str(kinds.get(sent_off, "")), "red", "a red card did not ban")
	kinds.clear()
	for row in SeasonAvailability.rows(away):
		kinds[str(row["player_id"])] = str(row["grade"])
	assert_eq(str(kinds.get(two_yellows, "")), "second_yellow", "a second yellow did not ban")

func test_a_threshold_past_its_cut_off_does_not_ban() -> void:
	var club := _first_club()
	var id := str(TeamData.get_team(club)["starters"][4]["id"])
	for i in range(5):
		_book(club, id, 1, 0, 25)
	assert_eq(SeasonAvailability.absences(club).size(), 0,
		"five cards after the nineteenth game still banned")


func test_the_strongest_xi_skips_the_ruled_out() -> void:
	var club := _first_club()
	var team := TeamData.get_team(club)
	var star: Dictionary = team["starters"][0]
	var id := str(star["id"])
	SeasonAvailability.suspend(id, club, 1, "red", "2026-08-15")
	var xi := StrongestXI.pick(TeamData.get_team(club))
	assert_eq(xi.size(), 11, "the XI is not eleven")
	for p in xi:
		assert_ne(str(p["id"]), id, "a suspended player was picked")

	LeagueSeason.active = null
	var full := StrongestXI.pick(TeamData.get_team(club))
	var back := false
	for p in full:
		if str(p["id"]) == id:
			back = true
	assert_true(back, "single-match mode dropped a player")
	LeagueSeason.active = season

func test_a_short_squad_still_fields_eleven() -> void:
	var club := _first_club()
	var team := TeamData.get_team(club)
	var pool: Array = []
	pool.append_array(team["starters"])
	pool.append_array(team["bench"])
	for p in pool:
		SeasonAvailability.suspend(str(p["id"]), club, 2, "red", "2026-08-15")
	var xi := StrongestXI.pick(TeamData.get_team(club))
	assert_eq(xi.size(), 11, "a club with nobody fit did not field eleven")
	PLDatabase.execute("DELETE FROM league_absence WHERE club_id = ?;", [club])


func test_an_auto_fixture_can_injure_and_the_season_keeps_it() -> void:
	var club := _first_club()
	PLDatabase.execute("DELETE FROM league_absence;")
	var events: Array = []
	var xi := StrongestXI.pick(TeamData.get_team(club))
	for i in range(12):
		events.append_array(MatchEvents.side(900 + i, "fx-injury-%d" % i, club, xi, 0))
	var hurt := 0
	for e in events:
		if str(e.get("kind", "")) == "injury":
			hurt += 1
	assert_gte(hurt, 1, "twelve auto fixtures never injured a body")
	SeasonAvailability.apply_fixture(1, "2026-08-15", [{
		"club_id": club, "rows": [], "events": events,
	}], SEED)
	var injured := 0
	for row in SeasonAvailability.rows(club):
		if str(row["kind"]) == "injury":
			injured += 1
			assert_gte(int(row["days_left"]), 3, "the injury has no days")
	assert_gte(injured, 1, "the injury did not reach the season")
	PLDatabase.execute("DELETE FROM league_absence;")

func test_a_watched_fixture_settles_cards_and_injuries_through_the_same_path() -> void:
	var engine = MatchEngine.new(SEED, "ENG-MUN1", "ENG-MCI1")
	engine.tick()
	var hurt = engine.players[0]
	var booked = engine.players[1]
	hurt.injured = true
	booked.yellow = 2
	LeagueSettle.watch(season.record, engine, [], SEED, "2026-08-15", 1)
	var kinds := {}
	for row in SeasonAvailability.rows(str(engine.teams[hurt.team]["id"])):
		kinds[str(row["player_id"])] = str(row["kind"])
	assert_eq(str(kinds.get(str(hurt.key), "")), "injury",
		"the engine's injury did not reach the season")
	assert_eq(str(kinds.get(str(booked.key), "")), "suspension",
		"a second yellow in the engine did not ban")

func test_backing_out_of_a_briefing_cancels_the_watch() -> void:
	var fixtures := season.plan()
	var held := str(fixtures[0]["id"])
	season.set_watch(held, true)
	season.advance()
	var watch := season.start_watch(held)
	assert_false(watch.is_empty(), "the fixture did not start")
	season.cancel_watch()
	assert_eq(season.watching_fixture, "", "the season is still waiting for the fixture")
	season.set_watch(held, false)


func _unavailable(club: String, player_id: String, competition: String) -> bool:
	return SeasonAvailability.unavailable(club, competition).has(player_id)


func _picked(xi: Array, player_id: String) -> bool:
	for p in xi:
		if str(p["id"]) == player_id:
			return true
	return false


func test_a_cup_red_bans_the_cup_and_leaves_the_league_alone() -> void:
	var club := _first_club()
	var league := SeasonAvailability.league_of(club)
	var id := str(TeamData.get_team(club)["starters"][0]["id"])
	_book(club, id, 0, 1, 3, "FAC")
	assert_true(_unavailable(club, id, "FAC"), "the cup red did not ban")
	assert_false(_unavailable(club, id, league), "a cup red emptied the league XI")
	assert_true(_picked(StrongestXI.pick(TeamData.get_team(club), league), id),
		"a cup ban kept him out of the league XI")
	assert_false(_picked(StrongestXI.pick(TeamData.get_team(club), "FAC"), id),
		"the cup ban did not empty the cup XI")
	assert_true(WikiAbsence.statuses(club).has(id), "the encyclopedia lost the cup ban")
	SeasonAvailability.apply_fixture(4, "2026-08-22",
		[{"club_id": club, "rows": [], "events": []}], SEED, league)
	assert_true(_unavailable(club, id, "FAC"), "a league fixture served a cup ban")
	SeasonAvailability.apply_fixture(5, "2026-08-29",
		[{"club_id": club, "rows": [], "events": []}], SEED, "FAC")
	assert_false(_unavailable(club, id, "FAC"), "the cup fixture did not serve the cup ban")


func test_a_league_ban_does_not_empty_the_cup_xi() -> void:
	var club := _first_club()
	var league := SeasonAvailability.league_of(club)
	var id := str(TeamData.get_team(club)["starters"][0]["id"])
	SeasonAvailability.suspend(id, club, 1, "red", "2026-08-15")
	assert_true(_unavailable(club, id, league), "the league ban is missing")
	assert_false(_unavailable(club, id, "FAC"), "a league ban emptied the cup XI")
	assert_true(_picked(StrongestXI.pick(TeamData.get_team(club), "FAC"), id),
		"a league ban kept him out of the cup XI")


func test_a_cup_injury_keeps_him_out_of_every_competition() -> void:
	var club := _first_club()
	var id := str(TeamData.get_team(club)["starters"][7]["id"])
	SeasonAvailability.apply_fixture(3, "2026-08-15", [{
		"club_id": club, "rows": [],
		"events": [{"kind": "injury", "player_id": id, "club_id": club}],
	}], SEED, "FAC")
	assert_true(_unavailable(club, id, SeasonAvailability.league_of(club)),
		"a cup injury left him available in the league")
	assert_true(_unavailable(club, id, "UCL"), "a cup injury left him available in Europe")
	var kind := ""
	for row in SeasonAvailability.rows(club, "UCL"):
		if str(row["player_id"]) == id:
			kind = str(row["kind"])
	assert_eq(kind, "injury", "the body is not marked injured")


func test_cup_yellows_are_recorded_apart_from_the_league_table() -> void:
	var club := _first_club()
	var league := SeasonAvailability.league_of(club)
	var id := str(TeamData.get_team(club)["starters"][8]["id"])
	for i in range(4):
		_book(club, id, 1, 0, 1)
	for i in range(4):
		_book(club, id, 1, 0, 2, "FAC")
	assert_eq(SeasonAvailability.absences(club, "FAC").size(), 0,
		"four cup yellows banned a player")
	var counts := {}
	for row in PLDatabase.rows(
			"SELECT competition_id, yellows FROM league_discipline WHERE player_id = ?;",
			[id]):
		counts[str(row["competition_id"])] = int(row["yellows"])
	assert_eq(int(counts.get(league, 0)), 4, "the league yellow tally is wrong")
	assert_eq(int(counts.get("FAC", 0)), 4, "the cup yellow tally is wrong")
	_book(club, id, 1, 0, 3)
	assert_eq(SeasonAvailability.absences(club, league).size(), 1,
		"five league yellows did not ban")
	assert_eq(SeasonAvailability.absences(club, "FAC").size(), 0,
		"the league threshold banned in the cup")


func test_a_player_can_carry_an_injury_and_bans_in_two_competitions() -> void:
	var club := _first_club()
	var id := str(TeamData.get_team(club)["starters"][0]["id"])
	SeasonAvailability.suspend(id, club, 1, "red", "2026-08-15", "FAC")
	SeasonAvailability.suspend(id, club, 2, "red", "2026-08-15", "EFLC")
	SeasonAvailability.injure(id, club, "2026-08-15", "knock", 5, 1.0)
	var rows := SeasonAvailability.rows(club)
	assert_eq(rows.size(), 3, "one player cannot hold an injury and two bans at once")
	var seen := {}
	for row in rows:
		seen[str(row["competition_id"])] = int(row["matches_left"])
	assert_eq(int(seen.get("", -1)), 0, "the injury has no competition of its own")
	assert_eq(int(seen.get("FAC", 0)), 1, "the cup ban lost its length")
	assert_eq(int(seen.get("EFLC", 0)), 2, "the second cup ban lost its length")


func test_an_older_absence_table_gains_the_competition_key() -> void:
	var club := _first_club()
	var league := SeasonAvailability.league_of(club)
	var id := str(TeamData.get_team(club)["starters"][0]["id"])
	var hurt := str(TeamData.get_team(club)["starters"][1]["id"])
	_install_old_tables(club, id, hurt)
	LeagueSaveSchema.migrate()
	assert_true(SeasonAvailability.unavailable(club, league).has(id),
		"the old league ban lost its competition")
	assert_true(SeasonAvailability.unavailable(club, league).has(hurt),
		"the old injury left the body available")
	var mark := PLDatabase.row(
		"SELECT competition_id, yellow_mark FROM league_discipline WHERE player_id = ?;", [id])
	assert_eq(str(mark.get("competition_id", "")), league, "the old mark lost its competition")
	assert_eq(int(mark.get("yellow_mark", 0)), 5, "the old mark lost its count")


func _install_old_tables(club: String, id: String, hurt: String) -> void:
	PLDatabase.execute("ALTER TABLE league_absence RENAME TO league_absence_old;")
	PLDatabase.execute(
		"CREATE TABLE league_absence (player_id TEXT PRIMARY KEY, club_id TEXT NOT NULL, "
		+ "kind TEXT NOT NULL, grade TEXT NOT NULL DEFAULT '', "
		+ "days_left INTEGER NOT NULL DEFAULT 0, matches_left INTEGER NOT NULL DEFAULT 0, "
		+ "started_on TEXT NOT NULL DEFAULT '', due_on TEXT NOT NULL DEFAULT '', "
		+ "rate REAL NOT NULL DEFAULT 1.0);")
	PLDatabase.execute(
		"INSERT INTO league_absence VALUES (?, ?, 'suspension', 'red', 0, 2, "
		+ "'2026-08-15', '', 1.0);", [id, club])
	PLDatabase.execute(
		"INSERT INTO league_absence VALUES (?, ?, 'injury', 'knock', 7, 0, "
		+ "'2026-08-15', '2026-08-22', 1.0);", [hurt, club])
	PLDatabase.execute("DROP TABLE league_absence_old;")
	PLDatabase.execute("ALTER TABLE league_discipline RENAME TO league_discipline_old;")
	PLDatabase.execute(
		"CREATE TABLE league_discipline (player_id TEXT PRIMARY KEY, club_id TEXT NOT NULL, "
		+ "yellow_mark INTEGER NOT NULL DEFAULT 0);")
	PLDatabase.execute("INSERT INTO league_discipline VALUES (?, ?, 5);", [id, club])
	PLDatabase.execute("DROP TABLE league_discipline_old;")


func test_a_cup_briefing_lists_only_the_cup_bans() -> void:
	var club := _first_club()
	var other := str(TeamData.team_ids()[1])
	var id := str(TeamData.get_team(club)["starters"][0]["id"])
	SeasonAvailability.suspend(id, club, 1, "red", "2026-08-15", "FAC")
	var cup := PreMatchModel.build(club, other, {"competition_id": "FAC", "matchday": 3}, season)
	var listed: Array = []
	for row in cup["home_absences"]:
		listed.append(str(row["player_id"]))
	assert_true(listed.has(id), "the cup briefing hides a cup ban")
	assert_false(_picked(cup["home_xi"], id), "the cup XI fields a banned player")
	var league_view := PreMatchModel.build(club, other,
		{"competition_id": SeasonAvailability.league_of(club), "matchday": 3}, season)
	var shown: Array = []
	for row in league_view["home_absences"]:
		shown.append(str(row["player_id"]))
	assert_false(shown.has(id), "the league briefing lists a cup ban")
	assert_true(_picked(league_view["home_xi"], id), "the league XI drops a cup-banned player")
