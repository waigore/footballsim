extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_clauses_446")
var CACHE_DIR := TestScratch.dir("cache_market_clauses_446")
const SEED := 6460
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


func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[club_id]).get("id", ""))


func _club_of(player_id: String) -> String:
	return str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player_id]).get("club_id", ""))


func _terms(player_id: String, overrides: Dictionary = {}) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player_id)
	var terms := {
		"fee": 5_000_000, "wage": int(contract.get("wage", 5000)), "years": 4,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0,
	}
	for key in overrides:
		terms[key] = overrides[key]
	return terms


func _propose(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary, date: String = DATE) -> String:
	var out := MarketDeals.propose(season, from, to, player, terms, date)
	assert_true(str(out.get("deal", "")) != "", "the deal was not proposed")
	return str(out.get("deal", ""))


func _seal(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary, date: String = DATE) -> Dictionary:
	var deal := _propose(season, from, to, player, terms, date)
	MarketDeals.agree(deal, date)
	return MarketDeals.seal(deal, date)


func test_a_fee_at_the_clause_signs_without_seller_consent() -> void:
	var season := _fresh("Clause Meets")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var clause := MarketAttribution.release_clause(player)
	assert_gt(clause, 0, "the seeded contract carries no clause")
	var cut := _terms(player, {"fee": clause, "wage": maxi(int(_terms(player)["wage"]) - 1000, 1)})
	var done := _seal(season, from, to, player, cut)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"a fee at the clause did not sign: %s" % str(done.get("reason", "")))
	assert_eq(_club_of(player), to, "the clause move did not land")


func test_a_fee_below_the_clause_still_needs_consent() -> void:
	var season := _fresh("Clause Miss")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var cut := _terms(player, {"fee": 5_000_000,
		"wage": maxi(int(_terms(player)["wage"]) - 1000, 1)})
	var deal := _propose(season, from, to, player, cut)
	var refused := MarketDeals.agree(deal, DATE)
	assert_eq(str(refused.get("reason", "")), MarketDealRules.CONSENT,
		"a below-clause pay cut signed without consent")
	assert_eq(_club_of(player), from, "a refused deal moved the player")


func test_a_second_permanent_sale_pays_the_sell_on() -> void:
	var season := _fresh("Sell On")
	var first := _club_in("PL", 0)
	var middle := _club_in("PL", 1)
	var last := _club_in("PL", 2)
	var player := _player_at(first)
	var sold := _seal(season, first, middle, player, _terms(player, {"sell_on": 0.1}))
	assert_eq(str(sold.get("state", "")), MarketDealRecords.SIGNED, "the first sale did not sign")
	var club_cash := MarketFinance.cash(first)
	var second := _seal(season, middle, last, player, _terms(player, {"fee": 8_000_000}))
	assert_eq(str(second.get("state", "")), MarketDealRecords.SIGNED, "the second sale did not sign")
	assert_eq(MarketFinance.cash(first), club_cash + 800_000,
		"the former club did not receive the ten percent sell-on")
	var line := PLDatabase.row(
		"SELECT amount FROM club_ledger WHERE club_id = ? AND kind = 'sell_on' "
		+ "ORDER BY id DESC LIMIT 1;", [first])
	assert_eq(int(line.get("amount", 0)), 800_000, "the former club's sell-on line is wrong")


func test_the_agent_and_bonus_post_to_the_ledger() -> void:
	var season := _fresh("Agent Bonus")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var cash := MarketFinance.cash(to)
	var deal := _propose(season, from, to, player,
		_terms(player, {"fee": 2_000_000, "agent_fee": 500_000, "signing_bonus": 300_000}))
	var cost := MarketAttribution.buyer_cost(MarketDealRecords.load(deal))
	MarketDeals.agree(deal, DATE)
	var done := MarketDeals.seal(deal, DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the deal did not sign")
	assert_eq(MarketFinance.cash(to), cash - cost, "the buyer did not pay the full deal cost")
	var agent := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM club_ledger WHERE club_id = ? AND kind = 'agent' AND deal_id = ?;",
		[to, deal])
	assert_gte(int(agent.get("n", 0)), 2, "the ledger has no agent line and no bonus line on the deal")


func test_solidarity_spreads_five_percent_over_the_youth_spells() -> void:
	var season := _fresh("Solidarity")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var birth := str(PLDatabase.row("SELECT date_of_birth FROM player WHERE id = ?;",
		[player]).get("date_of_birth", ""))
	assert_true(birth != "", "the seeded player has no date of birth")
	PLDatabase.execute("DELETE FROM player_history WHERE player_id = ?;", [player])
	PLDatabase.execute(
		"INSERT INTO player_history (player_id, season_index, club_id, competition_id, kind, "
		+ "from_date, to_date) VALUES (?, 0, ?, 'PL', 'spell', ?, ?);",
		[player, from, _aged(birth, 13), _aged(birth, 17)])
	PLDatabase.execute(
		"INSERT INTO player_history (player_id, season_index, club_id, competition_id, kind, "
		+ "from_date, to_date) VALUES (?, 0, ?, 'PL', 'spell', ?, ?);",
		[player, to, _aged(birth, 17), _aged(birth, 21)])
	var shares := MarketAttribution.solidarity_shares(player, 10_000_000)
	assert_eq(shares.size(), 2, "the two eligible spells did not split the solidarity")
	var total := 0
	for row in shares:
		total += int((row as Dictionary).get("amount", 0))
	assert_eq(total, 500_000, "the shares do not sum to five percent of the fee")
	var done := _seal(season, from, to, player, _terms(player, {"fee": 10_000_000}))
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the deal did not sign")
	var paid := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM club_ledger WHERE kind = 'solidarity';")
	assert_gte(int(paid.get("n", 0)), 2, "the solidarity did not post both shares")


func test_training_compensation_is_charged_on_a_first_professional_move() -> void:
	var season := _fresh("Training")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	PLDatabase.execute("UPDATE player SET age = 18 WHERE id = ?;", [player])
	var birth := str(PLDatabase.row("SELECT date_of_birth FROM player WHERE id = ?;",
		[player]).get("date_of_birth", ""))
	var home := str(PLDatabase.row("SELECT homegrown_club_id FROM player WHERE id = ?;",
		[player]).get("homegrown_club_id", ""))
	assert_true(home != "", "the seeded player has no homegrown club")
	PLDatabase.execute("DELETE FROM player_history WHERE player_id = ?;", [player])
	PLDatabase.execute(
		"INSERT INTO player_history (player_id, season_index, club_id, competition_id, kind, "
		+ "from_date, to_date) VALUES (?, 0, ?, 'PL', 'spell', ?, ?);",
		[player, from, _aged(birth, 13), _aged(birth, 16)])
	if home == to:
		return
	var due := MarketAttribution.training_due(player, to, 4_000_000)
	assert_false(due.is_empty(), "a first professional move owed no training fee")
	var done := _seal(season, from, to, player, _terms(player, {"fee": 4_000_000}))
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the first move did not sign")
	assert_true(MarketAttribution.training_due(player, to, 4_000_000).is_empty(),
		"a second move was still charged training compensation")
	var line := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM club_ledger WHERE kind = 'training' AND club_id = ?;", [home])
	assert_gte(int(line.get("n", 0)), 1, "the homegrown club received no training fee")


func test_a_seeded_player_has_a_homegrown_club_and_no_invented_spells() -> void:
	var season := _fresh("Bootstrap Fiction")
	var rows := PLDatabase.rows(
		"SELECT id, club_id, homegrown_club_id FROM player ORDER BY club_id, id LIMIT 40;")
	for row in rows:
		assert_eq(str(row.get("homegrown_club_id", "")), str(row.get("club_id", "")),
			"a seeded player's homegrown club is not his seed club")
	var spells := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_history WHERE kind = 'spell';")
	assert_eq(int(spells.get("n", 0)), 0, "the seed invented career spells")


func test_the_inspector_itemises_fee_agent_bonus_sell_on_and_solidarity() -> void:
	var season := _fresh("Inspector")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player,
		_terms(player, {"fee": 3_000_000, "agent_fee": 150_000, "signing_bonus": 100_000}))
	var extras := MarketAttribution.extras(MarketDealRecords.load(deal))
	assert_true(extras.has("sell_on"), "the extras do not carry the sell-on")
	assert_true(extras.has("solidarity"), "the extras do not carry the solidarity")
	assert_true(extras.has("training"), "the extras do not carry the training fee")
	var cost := MarketAttribution.buyer_cost(MarketDealRecords.load(deal))
	assert_gte(cost, 3_250_000, "the buyer cost omits the agent or the bonus")


func _aged(birth: String, years: int) -> String:
	return FixtureCalendar.add_years(birth, years)


func test_the_clauses_verb_runs_without_the_deal_engine_loaded() -> void:
	var verb: Script = load("res://tools/market_sim/clauses.gd")
	var out: Dictionary = verb.run({"seed": "7046", "fee": "40m", "clause": "35m",
		"sell-on": "10", "solidarity": "1"})
	assert_true(bool(out.get("ok", false)), "the clauses verb did not settle: %s" % str(out))
	assert_true(bool(out.get("clause_met", false)), "a fee at the clause did not count")
	assert_eq(int(out.get("buyer_cost", 0)) >= int(out.get("fee", 0)), true,
		"the buyer cost is below the fee")
	assert_false((out.get("sell_on", {}) as Dictionary).is_empty(), "the verb lost the sell-on")
	assert_false((out.get("solidarity", []) as Array).is_empty(), "the verb lost the solidarity")


func test_the_attribution_edge_cases() -> void:
	var season := _fresh("Attribution Edges")
	assert_eq(MarketAttribution.release_clause(""), 0, "an empty player has a clause")
	assert_false(MarketAttribution.clause_met("", 1), "an empty player met a clause")
	assert_true((MarketAttribution.extras({}).get("sell_on", {}) as Dictionary).is_empty(),
		"an empty deal paid a sell-on")
	assert_true(MarketAttribution.solidarity_shares("", 1_000_000).is_empty(),
		"an empty player earned solidarity")
	assert_true(MarketAttribution.solidarity_shares("nobody", 1_000_000).is_empty(),
		"an unknown player earned solidarity")
	var player := _player_at(_club_in("PL", 0))
	PLDatabase.execute("UPDATE player SET date_of_birth = '' WHERE id = ?;", [player])
	assert_true(MarketAttribution.solidarity_shares(player, 1_000_000).is_empty(),
		"a player with no birth date earned solidarity")
	assert_true(MarketAttribution.training_due("", "", 1_000_000).is_empty(),
		"an empty player owed training")
	assert_true(MarketAttribution.training_due(player, _club_in("PL", 1), 0).is_empty(),
		"a free move owed training")
	MarketAttribution.apply({}, DATE)


func test_the_sell_on_needs_a_former_club_that_is_not_the_seller() -> void:
	var season := _fresh("Sell On Edges")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var cash_from := MarketFinance.cash(from)
	var fee := 6_000_000
	var done := _seal(season, from, to, player, _terms(player, {"fee": fee, "sell_on": 0.0}))
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the no-sell-on deal did not sign")
	assert_eq(MarketFinance.cash(from), cash_from + fee, "a zero sell-on cost the seller the fee")
