extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_youth_451")
var CACHE_DIR := TestScratch.dir("cache_youth_451")
const SEED := 7451
const DATE := "2026-08-20"

var opened: Array = []


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	for season in opened:
		(season as LeagueSeason).close()
	opened.clear()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _fresh(name: String, seed_value: int = SEED) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", seed_value, ["PL"], false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	return season


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func _clubs() -> Array:
	var out: Array = []
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;"):
		out.append(str(row["id"]))
	return out


func _youth(club_id: String, season_index: int = 0) -> Array:
	return PLDatabase.rows("SELECT * FROM player WHERE club_id = ? AND id LIKE ? ORDER BY id;",
		[club_id, "Y%d-%%" % season_index])


func test_every_club_gains_two_to_eight_youth() -> void:
	var season := _fresh("Youth Intake")
	var intake := YouthIntake.apply(season, 0, DATE)
	assert_true(bool(intake.get("ok", false)), "the intake refused")
	assert_eq(int(intake.get("clubs", 0)), 20, "the intake missed a club")
	for club_id in _clubs():
		var made := _youth(club_id).size()
		assert_between(made, 2, 8, "%s gained %d youth" % [club_id, made])
	assert_eq(int(intake.get("players", 0)), _count(
		"SELECT COUNT(*) AS n FROM player WHERE id LIKE 'Y0-%';"),
		"the intake count disagrees with the table")


func test_a_youth_is_sixteen_to_eighteen_homegrown_and_on_a_three_year_deal() -> void:
	var season := _fresh("Youth Shape")
	YouthIntake.apply(season, 0, DATE)
	var rows := PLDatabase.rows("SELECT * FROM player WHERE id LIKE 'Y0-%' ORDER BY id;")
	assert_gt(rows.size(), 0, "the intake wrote no player")
	for row in rows:
		var id := str(row["id"])
		assert_between(int(row["age"]), 16, 18, "%s is %d" % [id, int(row["age"])])
		assert_eq(str(row.get("homegrown_club_id", "")), str(row["club_id"]),
			"%s is not homegrown at his club" % id)
		var contract := MarketDealRecords.active_contract(id)
		assert_false(contract.is_empty(), "%s has no contract" % id)
		assert_eq(str(contract.get("club_id", "")), str(row["club_id"]),
			"%s's contract is at the wrong club" % id)
		var years := int(str(contract.get("start_date", "")).substr(0, 4))
		assert_eq(int(str(contract.get("end_date", "")).substr(0, 4)) - years, 3,
			"%s's deal is not three seasons long" % id)
		var registration := MarketDealRecords.registration(id,
			str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
				[str(row["club_id"])]).get("competition_id", "")))
		assert_false(registration.is_empty(), "%s has no registration" % id)
		assert_eq(int(registration.get("u21_exempt", 0)), 1, "%s is not U21-exempt" % id)


func test_no_club_exceeds_its_list_after_intake() -> void:
	var season := _fresh("Youth Slots")
	YouthIntake.apply(season, 0, DATE)
	for club_id in _clubs():
		assert_lte(MarketLists.slots_used(club_id), MarketLists.SLOTS,
			"%s passed the list ceiling" % club_id)


func test_a_fixed_seed_produces_the_same_names() -> void:
	var one := _fresh("Youth Names One")
	YouthIntake.apply(one, 0, DATE)
	var first: Array = []
	for row in PLDatabase.rows("SELECT name FROM player WHERE id LIKE 'Y0-%' ORDER BY id LIMIT 40;"):
		first.append(str(row["name"]))
	var two := _fresh("Youth Names Two")
	YouthIntake.apply(two, 0, DATE)
	var second: Array = []
	for row in PLDatabase.rows("SELECT name FROM player WHERE id LIKE 'Y0-%' ORDER BY id LIMIT 40;"):
		second.append(str(row["name"]))
	assert_eq(first.size(), 40, "the probe found too few youth")
	assert_eq(second, first, "the same seed produced different names")


func test_a_generated_player_can_be_signed_like_any_other() -> void:
	var season := _fresh("Youth Market")
	YouthIntake.apply(season, 0, DATE)
	var from: String = str(_clubs()[0])
	var to: String = str(_clubs()[1])
	var row: Dictionary = _youth(from)[0]
	var player_id := str(row["id"])
	var wage := int(MarketDealRecords.active_contract(player_id).get("wage", 1))
	assert_true(bool(MarketWindows.state(DATE, "ENG").get("open", false)),
		"the probe date is outside the window")
	var terms := {"fee": 100_000, "wage": wage, "years": 3, "agent_fee": 0,
		"signing_bonus": 0, "sell_on": 0.0}
	var deal := MarketDeals.propose(season, from, to, player_id, terms, DATE)
	var agreed := MarketDeals.agree(str(deal.get("deal", "")), DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.AGREED,
		"the generated player refused the move: %s" % str(agreed.get("reason", "")))
	var done := MarketDeals.seal(str(deal.get("deal", "")), DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"the generated player did not sign")
	assert_eq(str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player_id]).get("club_id", "")), to, "the generated player did not move")


func test_retirement_certainly_takes_a_forty_year_old_and_frees_his_records() -> void:
	assert_eq(SeasonAgeing.chance(40), 1.0, "a forty-year-old can stay on")
	var season := _fresh("Youth Retirement")
	YouthIntake.apply(season, 0, DATE)
	var row := PLDatabase.row("SELECT id, club_id FROM player WHERE id LIKE 'Y0-%' ORDER BY id LIMIT 1;")
	var player_id := str(row["id"])
	PLDatabase.execute("UPDATE player SET age = 40, date_of_birth = '' WHERE id = ?;", [player_id])
	var retired := SeasonAgeing.retire(season, 1, DATE)
	assert_gte(retired, 1, "the intake's forty-year-old survived")
	assert_true(PLDatabase.row("SELECT id FROM player WHERE id = ?;", [player_id]).is_empty(),
		"the retired player left his row")
	assert_eq(_count("SELECT COUNT(*) AS n FROM player_contract WHERE player_id = ?;", [player_id]),
		0, "the retired player left a contract")
	assert_eq(_count("SELECT COUNT(*) AS n FROM player_registration WHERE player_id = ?;",
		[player_id]), 0, "the retired player left a registration")


func test_the_rollover_runs_intake_after_the_review() -> void:
	var season := _fresh("Youth Rollover")
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = 2, away_goals = 1 "
			+ "WHERE id = ?;", [str(row["id"])])
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	var result := SeasonRollover.apply(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused")
	var youth: Dictionary = result.get("youth", {})
	assert_true(bool(youth.get("ok", false)), "the rollover skipped intake")
	assert_gt(int(youth.get("players", 0)), 0, "the rollover wrote no youth")
	assert_eq(_count("SELECT COUNT(*) AS n FROM player WHERE id LIKE 'Y1-%';"),
		int(youth.get("players", 0)), "the rollover intake is not in the table")


func test_the_isolated_youth_run_repeats_its_names() -> void:
	var script: Script = load("res://tools/market_sim/youth.gd")
	var first: Dictionary = script.run({"seasons": "3", "clubs": "20", "seed": "7051"})
	assert_true(bool(first.get("ok", false)), "the isolated youth run refused")
	assert_eq(int(first.get("over_40", -1)), 0, "a forty-year-old survived the isolated run")
	var log: Array = first.get("log", [])
	assert_eq(log.size(), 3, "the isolated run did not cover three seasons")
	for entry in log:
		assert_between(int((entry as Dictionary).get("intake_players", 0)), 40, 160,
			"a season's intake is off its band")
	var second: Dictionary = script.run({"seasons": "3", "clubs": "20", "seed": "7051"})
	assert_true(bool(second.get("ok", false)), "the repeated youth run refused")
	assert_eq(JSON.stringify(second.get("names", [])), JSON.stringify(first.get("names", [])),
		"a repeated isolated run changed its names")
