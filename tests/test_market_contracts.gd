extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_contracts_441")
var CACHE_DIR := TestScratch.dir("cache_market_contracts_441")
const SEED := 6120
const REVIEW := "2027-07-02"

var opened: Array = []
var shared: LeagueSeason = null


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
	shared = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _fresh(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"], false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	shared = null
	return season


func _shared() -> LeagueSeason:
	if shared != null and LeagueSeason.active == shared:
		return shared
	shared = _fresh("Contracts Read")
	return shared


func _contract(player_id: String) -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM player_contract WHERE player_id = ? AND status = 'active';", [player_id])


func _worst_player() -> Dictionary:
	return PLDatabase.row(
		"SELECT id, club_id, ovr FROM player WHERE club_id <> '' ORDER BY ovr, id LIMIT 1;")


func _best_player() -> Dictionary:
	return PLDatabase.row(
		"SELECT id, club_id, ovr FROM player WHERE club_id <> '' ORDER BY ovr DESC, id LIMIT 1;")


func _end_at(player_id: String, date: String) -> void:
	PLDatabase.execute(
		"UPDATE player_contract SET end_date = ? WHERE player_id = ? AND status = 'active';",
		[date, player_id])


func _count(sql: String) -> int:
	return int(PLDatabase.row(sql).get("n", 0))


func test_every_player_in_a_new_save_holds_a_contract() -> void:
	var season := _shared()
	assert_not_null(season, "the save was not created")
	var players := _count("SELECT COUNT(*) AS n FROM player;")
	assert_eq(MarketContracts.active_count(), players, "a new save leaves players uncontracted")
	var clubs := _count("SELECT COUNT(DISTINCT id) AS n FROM club;")
	assert_eq(_count("SELECT COUNT(DISTINCT club_id) AS n FROM player_contract WHERE status = 'active';"),
		clubs, "a new save leaves clubs without a contracted squad")
	assert_eq(MarketContracts.free_agent_count(), 0, "a new save opens with free agents")


func test_the_bootstrap_stays_inside_its_bounds() -> void:
	var season := _shared()
	assert_eq(_count("SELECT COUNT(DISTINCT start_date) AS n FROM player_contract;"), 1,
		"the bootstrap did not start every contract on one day")
	var start := str(PLDatabase.row("SELECT MIN(start_date) AS d FROM player_contract;").get("d", ""))
	assert_true(start.length() == 10, "the contracts carry no start date")
	assert_eq(start, str(season.save.rules.get("season_start", "")),
		"the contracts do not start on the season's first day")
	var legal: Array = []
	for years in range(1, 5):
		legal.append(FixtureCalendar.add_days(FixtureCalendar.add_years(start, years), -1))
	var stray := _count(
		"SELECT COUNT(*) AS n FROM player_contract WHERE end_date NOT IN ('%s');"
		% "', '".join(PackedStringArray(legal)))
	assert_eq(stray, 0, "a contract ends off its term")
	for date in legal:
		assert_gte(_count("SELECT COUNT(*) AS n FROM player_contract WHERE end_date = '%s';" % date),
			1, "no contract ends on %s" % date)
	var unpaid := _count("SELECT COUNT(*) AS n FROM player_contract WHERE wage <= 0;")
	assert_eq(unpaid, 0, "a contracted player earns nothing")
	for club in PLDatabase.rows("SELECT id, competition_id, capacity FROM club ORDER BY id;"):
		var budget := MarketWages.wage_budget(club)
		var bill := MarketContracts.wage_bill(str(club["id"])) * 52
		assert_gte(budget, bill, "%s pays more than 55%% of its revenue" % str(club["id"]))


func test_the_player_page_reads_the_contract_block() -> void:
	_shared()
	var row := _best_player()
	var page := WikiPlayer.page(str(row["id"]))
	var block := _contract_block(page)
	assert_false(block.is_empty(), "the player page has no contract block")
	var items := _items(block)
	assert_has(items.keys(), "WAGE", "the contract block lost the wage")
	assert_has(items.keys(), "EXPIRES", "the contract block lost the expiry")
	assert_has(items.keys(), "EMPLOYMENT", "the contract block lost the employment")
	assert_has(items.keys(), "CLAUSE", "the contract block lost the clause")
	assert_has(items.keys(), "CLUB", "the contract block lost the club")
	assert_true(str(items["WAGE"]).ends_with("/WK"), "the wage does not read weekly")


func test_expiry_opens_free_agency() -> void:
	var season := _fresh("Contracts Expiry")
	var row := _worst_player()
	var player_id := str(row["id"])
	_end_at(player_id, "2027-07-01")
	var before := MarketContracts.free_agent_count()
	var review := MarketContracts.review(season.save, 1, REVIEW)
	assert_gte(int(review["expired"]), 1, "the review expired nobody")
	var contract := MarketContracts.of_player(player_id)
	assert_eq(str(contract.get("status", "")), MarketContracts.EXPIRED, "the contract stayed active")
	var registered := PLDatabase.row("SELECT club_id FROM player WHERE id = ?;", [player_id])
	assert_eq(str(registered.get("club_id", "x")), "", "a free agent still has a club")
	assert_eq(MarketContracts.free_agent_count(), before + int(review["expired"]),
		"the free agents do not match the exits")
	var agents: Array = []
	for agent in MarketContracts.free_agents(500):
		agents.append(str(agent["id"]))
	assert_true(agents.has(player_id), "the expired player is not in the free-agent pool")
	var closed := PLDatabase.row(
		"SELECT to_date FROM player_history WHERE player_id = ? AND kind = 'spell';", [player_id])
	assert_eq(str(closed.get("to_date", "")), "2027-07-01", "the spent spell was not written")


func test_a_top_xi_option_extends_one_year_at_ten_percent() -> void:
	var season := _fresh("Contracts Option")
	var row := _best_player()
	var player_id := str(row["id"])
	var before := _contract(player_id)
	assert_false(before.is_empty(), "the best player had no contract")
	MarketContracts.exercise_option(player_id)
	_end_at(player_id, "2027-07-01")
	var review := MarketContracts.review(season.save, 1, REVIEW)
	assert_gte(int(review["exercised"]), 1, "no option was exercised")
	var after := _contract(player_id)
	assert_false(after.is_empty(), "the exercised player lost his contract")
	assert_eq(str(after.get("end_date", "")), "2028-07-01", "the option did not add one year")
	assert_eq(int(after.get("wage", 0)), int(round(float(before["wage"]) * 1.1)),
		"the option year did not step the wage")
	assert_eq(str(after.get("club_id", "")), str(row["club_id"]), "the exercised player moved club")
	assert_eq(int(after.get("option_years", -1)), 0, "the option was not spent")


func test_god_declining_lets_him_expire() -> void:
	var season := _fresh("Contracts Decline")
	var row := _best_player()
	var player_id := str(row["id"])
	MarketContracts.exercise_option(player_id)
	assert_true(MarketContracts.decline_option(player_id), "god could not decline the option")
	_end_at(player_id, "2027-07-01")
	var review := MarketContracts.review(season.save, 1, REVIEW)
	assert_gte(int(review["expired"]), 1, "the declined contract did not expire")
	var contract := MarketContracts.of_player(player_id)
	assert_eq(str(contract.get("status", "")), MarketContracts.EXPIRED,
		"a declined contract was extended anyway")
	var page := WikiPlayer.page(player_id)
	var items := _items(_contract_block(page))
	assert_eq(str(items.get("EMPLOYMENT", "")), "FREE AGENT",
		"the free agent's page still names a contract")


func test_a_mover_keeps_his_injury() -> void:
	_shared()
	var row := _worst_player()
	var player_id := str(row["id"])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_absence (player_id, club_id, kind, grade, days_left) "
		+ "VALUES (?, ?, 'injury', 'knock', 9);", [player_id, str(row["club_id"])])
	assert_eq(MarketContracts.rehome(player_id, "ENG-MUN1"), 1, "the injury was not re-homed")
	var moved := PLDatabase.row(
		"SELECT club_id FROM league_absence WHERE player_id = ?;", [player_id])
	assert_eq(str(moved.get("club_id", "")), "ENG-MUN1", "the injury stayed at the old club")
	PLDatabase.execute("DELETE FROM league_absence WHERE player_id = ?;", [player_id])


func test_nothing_drifts_across_a_review() -> void:
	var season := _fresh("Contracts Steady")
	var row := PLDatabase.row(
		"SELECT c.player_id, c.wage, c.end_date, p.ovr FROM player_contract c "
		+ "JOIN player p ON p.id = c.player_id WHERE c.status = 'active' "
		+ "AND p.club_id = c.club_id ORDER BY c.end_date DESC LIMIT 1;")
	var player_id := str(row["player_id"])
	MarketContracts.review(season.save, 1, REVIEW)
	var after := PLDatabase.row("SELECT ovr FROM player WHERE id = ?;", [player_id])
	var contract := _contract(player_id)
	assert_eq(int(after.get("ovr", -1)), int(row["ovr"]), "a review moved a rating")
	assert_eq(int(contract.get("wage", -1)), int(row["wage"]), "a review moved a wage")
	assert_eq(str(contract.get("end_date", "")), str(row["end_date"]),
		"a review moved an expiry it did not own")


func test_the_rollover_keeps_every_squad_contracted() -> void:
	var season := _fresh("Contracts Rollover")
	for fixture in PLDatabase.rows("SELECT id FROM league_fixture;"):
		PLDatabase.execute("UPDATE league_fixture SET status = 'played' WHERE id = ?;",
			[str(fixture["id"])])
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	SeasonSettle.apply(season)
	var ratings := {}
	for player in PLDatabase.rows("SELECT id, ovr FROM player;"):
		ratings[str(player["id"])] = int(player["ovr"])
	var rollover := SeasonRollover.apply(season)
	assert_true(bool(rollover.get("ok", false)), "the rollover refused")
	var squads := _count("SELECT COUNT(*) AS n FROM player WHERE club_id <> '';")
	assert_eq(MarketContracts.active_count(), squads, "a rolled-over squad has an uncontracted player")
	assert_eq(MarketContracts.free_agent_count(), _count("SELECT COUNT(*) AS n FROM player WHERE club_id = '';"),
		"the free agents do not match the clubs")
	assert_eq(_count("SELECT COUNT(*) AS n FROM player_contract c JOIN player p ON p.id = c.player_id "
		+ "WHERE c.status = 'active' AND p.club_id <> c.club_id;"), 0,
		"an employer is not the club the player plays for")
	for player in PLDatabase.rows("SELECT id, ovr FROM player;"):
		var id := str(player["id"])
		if ratings.has(id):
			assert_eq(int(player["ovr"]), int(ratings[id]), "%s developed over the rollover" % id)


func test_the_bootstrap_is_a_one_off() -> void:
	var season := _shared()
	var before := MarketContracts.active_count()
	var again := MarketContracts.bootstrap(season.save, "2026-08-15")
	assert_true(bool(again.get("ok", false)), "a second bootstrap refused")
	assert_true(bool(again.get("skipped", false)), "a second bootstrap rewrote the market")
	assert_eq(MarketContracts.active_count(), before, "a second bootstrap changed the count")


func test_a_save_without_the_contracts_refuses_to_open() -> void:
	var season := _fresh("Contracts Legacy")
	var slug := season.save.slug
	PLDatabase.execute("UPDATE save_meta SET value = '18' WHERE key = 'db_version';")
	season.close()
	assert_null(LeagueSaveBoot.open(slug), "a save from before the market opened")
	assert_eq(LeagueSave.last_error, LeagueSave.NEW_SAVE_MESSAGE,
		"an old save refused without saying why")


func _contract_block(page: Dictionary) -> Dictionary:
	var found := {}
	var wanted := false
	for block in page.get("blocks", []):
		if str((block as Dictionary).get("k", "")) == "section" \
				and str((block as Dictionary).get("text", "")) == "CONTRACT":
			wanted = true
			continue
		if wanted and str((block as Dictionary).get("k", "")) == "kv":
			found = block
			break
	return found


func _items(block: Dictionary) -> Dictionary:
	var out := {}
	for item in block.get("items", []):
		var pair: Array = item
		out[str(pair[0])] = pair[1]
	return out
