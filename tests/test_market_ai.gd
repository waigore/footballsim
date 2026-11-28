extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_ai_450")
var CACHE_DIR := TestScratch.dir("cache_market_ai_450")
const SEED := 4501
const DATE := "2026-08-20"
const CLOSED := "2026-12-20"

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


func _fresh(name: String, mode: String = "fixture_days") -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", mode, SEED, ["PL"], false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	MarketTick.invalidate()
	MarketShortlist.reset()
	return season


func test_the_band_table_matches_at_every_boundary() -> void:
	var pairs := [[85, 90000000], [84, 45000000], [80, 45000000], [79, 22000000],
		[75, 22000000], [74, 10000000], [70, 10000000], [69, 4500000], [65, 4500000],
		[64, 1800000], [60, 1800000], [59, 400000]]
	for pair in pairs:
		assert_eq(MarketValuation.band_value(int(pair[0])), int(pair[1]),
			"OVR %d sits in the wrong band" % int(pair[0]))


func test_age_contract_and_position_multipliers_move_the_price() -> void:
	assert_eq(MarketValuation.age_mult(20), 1.15, "a 20-year-old loses the youth premium")
	assert_eq(MarketValuation.age_mult(27), 1.00, "the peak years are not neutral")
	assert_eq(MarketValuation.age_mult(40), 0.25, "an old player keeps his peak price")
	assert_eq(MarketValuation.contract_mult(4), 1.10, "a long deal loses its premium")
	assert_eq(MarketValuation.contract_mult(0), 0.55, "an expiring deal keeps its price")
	assert_eq(MarketValuation.position_mult("ST"), 1.12, "a striker is not worth a premium")
	assert_eq(MarketValuation.position_mult("UNKNOWN"), 1.00, "an unknown position fell through")
	var player := {"ovr": 77, "age": 24, "pos": "ST", "season": {}}
	var contract := {"end_date": FixtureCalendar.add_days(FixtureCalendar.add_years(
		"2026-08-15", 2), -1)}
	var worth := MarketValuation.value(player, contract, "2026-08-15")
	var expected := int(round(22000000.0 * 1.00 * 1.00 * 1.12))
	assert_eq(worth, expected, "the value did not multiply the band by every factor")


func test_form_moves_the_value_inside_its_band() -> void:
	var plain := {"ovr": 77, "age": 24, "pos": "ST", "season": {}}
	var hot := {"ovr": 77, "age": 24, "pos": "ST",
		"season": {"matches": 20, "goals": 20, "assists": 4}}
	var contract := {"end_date": "2028-08-14"}
	assert_eq(MarketValuation.value(plain, contract, "2026-08-15"),
		MarketValuation.value(plain, contract, "2026-08-15"), "valuation is not deterministic")
	assert_gt(MarketValuation.value(hot, contract, "2026-08-15"),
		MarketValuation.value(plain, contract, "2026-08-15"), "a hot scorer is worth no more")
	var cold := {"ovr": 77, "age": 24, "pos": "ST", "season": {"matches": 20, "goals": 0}}
	assert_lt(MarketValuation.value(cold, contract, "2026-08-15"),
		MarketValuation.value(plain, contract, "2026-08-15"), "a cold forward keeps his price")


func test_the_weekly_wage_floors_and_rounds() -> void:
	assert_eq(MarketValuation.weekly_wage(10000000, 0), 22000, "ten million reads the wrong wage")
	var floored := MarketValuation.weekly_wage(1000000, 100000)
	assert_eq(floored, 105000, "the current wage floor was not applied")
	assert_eq(floored % 10, 0, "the wage is not on its step")


func test_the_ui_value_equals_the_ai_valuation() -> void:
	var season := _fresh("AI Parity")
	var player_id := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = "
		+ "(SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1) "
		+ "ORDER BY ovr DESC LIMIT 1;").get("id", ""))
	assert_true(player_id != "", "no player to value")
	var player := PLRepository.shared().player(player_id)
	var contract := MarketDealRecords.active_contract(player_id)
	var ai_value := MarketValuation.value(player, contract, season.save.current_date())
	var page := WikiModel.page(WikiModel.PLAYER, player_id)
	var shown := ""
	for block in page.get("blocks", []):
		if str((block as Dictionary).get("k", "")) != "kv":
			continue
		for item in (block as Dictionary).get("items", []):
			if str(item[0]) == "VALUE":
				shown = str(item[1])
	assert_true(shown != "", "the player page carries no value")
	assert_eq(shown, MarketCurrency.format(ai_value), "the page value differs from the AI's")


func test_budget_is_cash_above_the_reserve() -> void:
	var season := _fresh("AI Budget")
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var finance := MarketFinance.club(club_id)
	var reserve := int(round(float(finance.get("revenue_base", 0))
		* MarketRules.number("need", "reserve_share", 0.10)))
	assert_eq(MarketNeeds.budget(club_id), int(finance.get("cash", 0)) - reserve,
		"the budget is not cash above the reserve")
	assert_true(MarketNeeds.budget(club_id) > 0, "a funded club has no budget")


func test_a_short_group_raises_a_need_and_a_full_one_does_not() -> void:
	var season := _fresh("AI Needs")
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var profile := MarketNeeds.profile(club_id)
	assert_false(profile.is_empty(), "the club has no need profile")
	assert_true(int(profile.get("median", 0)) > 0, "the tier median was not read")
	var groups: Dictionary = profile.get("groups", {})
	assert_eq(groups.size(), 4, "the profile does not group every position")
	for row in PLDatabase.rows("SELECT id FROM player WHERE club_id = ? AND pos IN "
			+ "('ST') OR (club_id = ? AND pos IN ('RW','LW'));", [club_id, club_id]):
		PLDatabase.execute("UPDATE player SET pos = 'GK' WHERE id = ?;", [str(row["id"])])
	MarketNeeds.invalidate()
	var after := MarketNeeds.profile(club_id)
	assert_gt(float((after["groups"] as Dictionary)["ATT"]["severity"]), 0.0,
		"an empty attack raised no need")
	var wants := MarketNeeds.wants(after)
	assert_gt(wants.size(), 0, "the needs produced no want")
	assert_eq(str(wants[0]["group"]), "ATT", "the emptiest group is not the first want")


func test_the_shortlist_reads_about_fifty_not_the_whole_world() -> void:
	var season := _fresh("AI Shortlist")
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var profile := MarketNeeds.profile(club_id)
	var ids := MarketShortlist.candidates(season, DATE, club_id, "MID",
		int(profile.get("median", 0)) + 8)
	assert_gt(ids.size(), 0, "the shortlist found no midfielder")
	assert_lte(ids.size(), MarketRules.count("ai", "shortlist_cap", 50),
		"the shortlist is wider than its cap")
	var seen := {}
	for id in ids:
		assert_false(seen.has(str(id)), "the shortlist repeats a player")
		seen[str(id)] = true
	assert_eq(MarketShortlist.candidates(season, DATE, club_id, "MID",
		int(profile.get("median", 0)) + 8), ids, "the same date built another shortlist")


func test_a_market_day_signs_a_deal_for_a_wanting_club() -> void:
	var season := _fresh("AI Deal")
	_empty_the_attack(_club())
	var before := _signed_count()
	for i in range(60):
		MarketAi.run_day(season, FixtureCalendar.add_days(DATE, i))
	assert_gt(_signed_count(), before, "a wanting club signed nobody all window")
	var row := PLDatabase.row("SELECT * FROM deal WHERE state = 'signed' ORDER BY rowid LIMIT 1;")
	assert_false(row.is_empty(), "no deal reached the table")
	var player_club := str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[str(row.get("player_id", ""))]).get("club_id", ""))
	assert_eq(player_club, str(row.get("to_club_id", "")), "the signed player is not at his buyer")
	assert_true(int(row.get("fee", 0)) > 0, "the deal moved no fee")
	assert_eq(int(row.get("wage", 0)) % 10, 0, "the wage is off its step")


func test_a_closed_window_stops_the_ai() -> void:
	var season := _fresh("AI Closed")
	_empty_the_attack(_club())
	var before := _signed_count()
	for i in range(12):
		MarketAi.run_day(season, FixtureCalendar.add_days(CLOSED, i))
	assert_eq(_signed_count(), before, "a closed window signed a deal")


func test_the_market_never_consumes_the_season_rng() -> void:
	var season := _fresh("AI RNG")
	var state := season.rng.state
	_empty_the_attack(_club())
	for i in range(10):
		MarketTick.step(season, FixtureCalendar.add_days(DATE, i))
	assert_eq(season.rng.state, state, "a market tick moved the season RNG")


func test_both_clock_modes_produce_the_same_transcript() -> void:
	var first := _transcript("fixture_days")
	var second := _transcript("every_day")
	assert_eq(first.size(), second.size(), "the two modes signed a different number of deals")
	assert_eq(first, second, "the two modes produced a different transcript")


func test_a_completeness_top_up_refills_a_thin_squad() -> void:
	_fresh("AI Complete")
	var club_id := _club()
	var donor := _club_at(1)
	for i in range(14):
		_release_one(donor)
	var before := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player WHERE club_id = ?;", [club_id]).get("n", 0))
	assert_true(before > 0, "the club has no players to thin")
	for i in range(before):
		_release_one(club_id)
	MarketNeeds.invalidate()
	var thin := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player WHERE club_id = ?;", [club_id]).get("n", 0))
	assert_lt(thin, 11, "the club was not thinned below eleven")
	assert_true(MarketContracts.free_agent_count() > 0, "no free agents to top up from")
	var signed := MarketCompleteness.ensure_club(club_id, DATE)
	assert_gt(signed, 0, "the top-up signed nobody")
	var after := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player WHERE club_id = ?;", [club_id]).get("n", 0))
	assert_gt(after, thin, "the top-up did not grow the squad")
	var need := MarketCompleteness.shortfall(club_id)
	assert_eq(int(need.get("players", 0)), 0, "the club is still short of eleven")
	assert_eq(int(need.get("keepers", 0)), 0, "the club still has no goalkeeper")


func test_the_ai_flag_can_be_switched_off_for_a_save() -> void:
	var season := _fresh("AI Off")
	assert_true(MarketTick.enabled(season), "a new save does not run the AI")
	season.save.put_meta(MarketTick.AI_KEY, "off")
	season.save.reload()
	assert_false(MarketTick.enabled(season), "the off switch did not take")


func _club() -> String:
	return str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))


func _club_at(index: int) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1 OFFSET ?;",
		[index]).get("id", ""))


func _empty_the_attack(club_id: String) -> void:
	PLDatabase.execute("UPDATE player SET club_id = '' WHERE club_id = ? AND pos IN "
		+ "('ST','RW','LW','CAM');", [club_id])
	MarketNeeds.invalidate()
	MarketShortlist.reset()


func _release_one(club_id: String) -> void:
	var row := PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr ASC LIMIT 1;", [club_id])
	var player_id := str(row.get("id", ""))
	if player_id == "":
		return
	PLDatabase.execute("UPDATE player SET club_id = '' WHERE id = ?;", [player_id])
	PLDatabase.execute(
		"UPDATE player_contract SET status = 'expired' WHERE player_id = ? "
		+ "AND status = 'active';", [player_id])


func _signed_count() -> int:
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM deal WHERE state = 'signed';").get("n", 0))


func _transcript(mode: String) -> Array:
	var season := _fresh("AI Transcript " + mode, mode)
	var guard := 0
	while season.save.status() != "complete" and guard < 300:
		season.advance()
		guard += 1
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT player_id, from_club_id, to_club_id, fee, state FROM deal ORDER BY opened_on, id;"):
		out.append("%s|%s|%s|%d|%s" % [str(row.get("player_id", "")),
			str(row.get("from_club_id", "")), str(row.get("to_club_id", "")),
			int(row.get("fee", 0)), str(row.get("state", ""))])
	return out
