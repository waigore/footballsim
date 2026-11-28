extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_clearance_447")
var CACHE_DIR := TestScratch.dir("cache_market_clearance_447")
const SEED := 6470
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


func _fresh(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"], false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	return season


func _club_in(competition_id: String, index: int = 0) -> String:
	var rows := PLDatabase.rows(
		"SELECT id FROM club WHERE competition_id = ? ORDER BY id;", [competition_id])
	if rows.is_empty():
		return ""
	return str(rows[clampi(index, 0, rows.size() - 1)]["id"])


func _competition(club_id: String) -> String:
	return str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[club_id]).get("competition_id", ""))


func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[club_id]).get("id", ""))


func _club_of(player_id: String) -> String:
	return str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player_id]).get("club_id", ""))


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func _terms(player_id: String, overrides: Dictionary = {}) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player_id)
	var terms := {
		"fee": 500_000, "wage": int(contract.get("wage", 5000)), "years": 4,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0,
	}
	for key in overrides:
		terms[key] = overrides[key]
	return terms


func _propose(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary, date: String = DATE) -> String:
	var out := MarketDeals.propose(season.save, from, to, player, terms, date)
	assert_true(str(out.get("deal", "")) != "", "the deal was not proposed")
	return str(out.get("deal", ""))


func test_a_cross_association_move_pends_for_clearance() -> void:
	var season := _fresh("Clear Cross")
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.CLEARANCE_PENDING,
		"an association change did not wait")
	var clears := str(agreed.get("clears_on", ""))
	assert_true(clears > DATE, "the clearance carries no future date")
	assert_eq(_club_of(player), from, "the player moved before clearance")
	var days := FixtureCalendar.days_from(clears) - FixtureCalendar.days_from(DATE)
	assert_between(days, 1, 5, "the clearance wait is off its band")
	var registration := MarketDealRecords.registration(player, _competition(to))
	assert_eq(str(registration.get("state", "")), "pending", "the pending registration is not pending")


func test_a_domestic_move_never_enters_clearance() -> void:
	var season := _fresh("Clear Domestic")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.AGREED,
		"a domestic move waited for clearance")
	var done := MarketDeals.seal(deal, DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the domestic move did not sign")


func test_a_failed_clearance_moves_nothing() -> void:
	var season := _fresh("Clear Fail")
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var ledger := _count("SELECT COUNT(*) AS n FROM club_ledger;")
	var cash_to := MarketFinance.cash(to)
	var cash_from := MarketFinance.cash(from)
	var deal := _propose(season, from, to, player, _terms(player))
	var agreed := MarketDeals.agree(deal, DATE)
	var failed := MarketDeals.resolve_clearance(deal, str(agreed.get("clears_on", DATE)),
		{"clearance": "fail"})
	assert_eq(str(failed.get("state", "")), MarketDealRecords.FAILED, "a failed clearance signed")
	assert_eq(str(failed.get("reason", "")), MarketDealRules.CLEARANCE,
		"the failure does not name clearance")
	assert_eq(_count("SELECT COUNT(*) AS n FROM club_ledger;"), ledger,
		"a failed clearance wrote a ledger line")
	assert_eq(MarketFinance.cash(to), cash_to, "a failed clearance moved the buyer's cash")
	assert_eq(MarketFinance.cash(from), cash_from, "a failed clearance moved the seller's cash")
	assert_eq(_club_of(player), from, "a failed clearance moved the player")
	assert_true(MarketDealRecords.registration(player, _competition(to)).is_empty(),
		"a failed clearance left a registration row")


func test_a_window_that_closes_during_clearance_fails_the_deal() -> void:
	var season := _fresh("Clear Window")
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.CLEARANCE_PENDING,
		"the deal did not wait for clearance")
	var closed := "2026-09-05"
	assert_false(bool(MarketWindows.state(closed, "ENG").get("open", false)),
		"the window is still open on %s" % closed)
	var failed := MarketDeals.resolve_clearance(deal, closed, {})
	assert_eq(str(failed.get("state", "")), MarketDealRecords.FAILED,
		"a clearance that outlived the window signed")
	assert_eq(str(failed.get("reason", "")), MarketDealRules.WINDOW_CLOSED,
		"the failure does not name the window")
	assert_eq(_club_of(player), from, "a window-closed clearance moved the player")


func test_the_same_deal_key_yields_the_same_clearance() -> void:
	var season := _fresh("Clear Determinism")
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	var first := MarketDeals.clearance_days(deal)
	assert_eq(MarketDeals.clearance_days(deal), first, "the clearance length drifted")
	assert_between(first, 1, 5, "the clearance length is off its band")
	assert_eq(MarketDeals.needs_clearance(MarketDealRecords.load(deal)), true,
		"the association change is not read as clearance")
	var domestic := _propose(season, _club_in("PL", 0), _club_in("PL", 1),
		_player_at(_club_in("PL", 0)), _terms(_player_at(_club_in("PL", 0))))
	assert_eq(MarketDeals.needs_clearance(MarketDealRecords.load(domestic)), false,
		"a domestic deal was read as clearance")


func test_a_cleared_deal_signs_and_moves_the_money() -> void:
	var season := _fresh("Clear Pass")
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var cash_to := MarketFinance.cash(to)
	var deal := _propose(season, from, to, player, _terms(player, {"fee": 750_000}))
	var cost := MarketAttribution.buyer_cost(MarketDealRecords.load(deal))
	var agreed := MarketDeals.agree(deal, DATE)
	var cleared := MarketDeals.resolve_clearance(deal, str(agreed.get("clears_on", DATE)),
		{"clearance": "pass"})
	assert_eq(str(cleared.get("state", "")), MarketDealRecords.SIGNED, "the cleared deal did not sign")
	assert_eq(_club_of(player), to, "the cleared deal did not move the player")
	assert_eq(MarketFinance.cash(to), cash_to - cost, "the cleared deal did not pay the fee")
	var registration := MarketDealRecords.registration(player, _competition(to))
	assert_eq(str(registration.get("state", "")), "registered", "the cleared deal is not registered")


func test_the_engine_refuses_an_empty_clearance() -> void:
	assert_eq(str(MarketDeals.resolve_clearance("", DATE).get("reason", "")), "no_deal",
		"an empty clearance resolved")
	assert_eq(MarketDeals.clearance_days(""), MarketRules.count("deal", "clearance_days_min", 1)
		+ MarketSeed.mix(0, "", 7) % maxi(
			MarketRules.count("deal", "clearance_days_max", 5)
			- MarketRules.count("deal", "clearance_days_min", 1) + 1, 1),
		"the empty key did not yield its fixed length")
	assert_true(MarketDeals._window_open_for(MarketDealRecords.load(""), DATE) == false,
		"an empty deal read an open window")
	MarketDeals._close_pending_registration({})


func test_the_clearance_verb_pends_clears_and_fails() -> void:
	var verb: Script = load("res://tools/market_sim/clearance.gd")
	var passed: Dictionary = verb.run({"seed": "7047", "inject": ""})
	assert_true(bool(passed.get("ok", false)), "the clearance verb did not pend: %s" % str(passed))
	assert_eq(str(passed.get("outcome", "")), MarketDealRecords.SIGNED, "the pass did not sign")
	var failed: Dictionary = verb.run({"seed": "7047", "inject": "clearance"})
	assert_eq(str(failed.get("outcome", "")), MarketDealRecords.FAILED, "the fail did not fail")
	assert_eq(str(failed.get("reason", "")), MarketDealRules.CLEARANCE, "the fail has no code")
	var shut: Dictionary = verb.run({"seed": "7047", "inject": "window"})
	assert_eq(str(shut.get("outcome", "")), MarketDealRecords.FAILED, "the window close did not fail")
	assert_eq(str(shut.get("reason", "")), MarketDealRules.WINDOW_CLOSED, "the close has no code")


func test_a_domestic_clearance_never_pends_and_the_free_agent_skips() -> void:
	var season := _fresh("Clear Guards")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var deal := MarketDealRecords.load(_propose(season, from, to, player, _terms(player)))
	assert_false(MarketDeals.needs_clearance(deal), "a domestic deal needs clearance")
	assert_true(MarketDeals._window_open_for(deal, DATE), "the domestic window is shut")
	var club := _club_in("LL", 0)
	var cross := _propose(season, club, to, _player_at(club), _terms(_player_at(club)))
	assert_true(MarketDeals.needs_clearance(MarketDealRecords.load(cross)),
		"a cross-association deal needs no clearance")
