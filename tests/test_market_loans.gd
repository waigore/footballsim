extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_loans_445")
var CACHE_DIR := TestScratch.dir("cache_market_loans_445")
const SEED := 6450
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


func _player_club(player_id: String) -> String:
	return str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player_id]).get("club_id", ""))


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func _terms(player_id: String, overrides: Dictionary = {}) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player_id)
	var terms := {
		"wage": int(contract.get("wage", 5000)), "wage_loanee": int(contract.get("wage", 5000)),
		"start_date": DATE, "end_date": "2027-05-31", "fee": 0,
		"option_kind": "none", "buy_fee": 0, "trigger_kind": "", "trigger_value": "",
	}
	for key in overrides:
		terms[key] = overrides[key]
	return terms


func _loan(season: LeagueSeason, parent: String, loanee: String, player: String,
		overrides: Dictionary = {}, date: String = DATE) -> Dictionary:
	var proposed := MarketLoans.propose(season, parent, loanee, player, _terms(player, overrides),
		date)
	var id := str(proposed.get("loan", ""))
	assert_true(id != "", "the loan was not proposed")
	return MarketLoans.seal(id, date)


func test_a_loan_moves_him_to_the_loanee_and_keeps_the_contract() -> void:
	var season := _fresh("Loan Register")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var contract_club := str(MarketDealRecords.active_contract(player).get("club_id", ""))
	var out := _loan(season, parent, loanee, player)
	assert_true(bool(out.get("ok", false)), "the loan did not seal: %s" % str(out.get("state", "")))
	assert_eq(_player_club(player), loanee, "player.club_id did not move to the loanee")
	assert_eq(str(MarketDealRecords.active_contract(player).get("club_id", "")), contract_club,
		"the parent lost the contract")
	var registration := MarketDealRecords.registration(player,
		str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [loanee]).get(
			"competition_id", "")))
	assert_eq(str(registration.get("kind", "")), "loan", "the registration is not a loan")
	assert_eq(str(registration.get("club_id", "")), loanee, "the registration is elsewhere")


func test_the_two_wage_shares_sum_to_the_weekly_wage() -> void:
	var season := _fresh("Loan Split")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	var out := _loan(season, parent, loanee, player, {"wage": wage, "wage_loanee": wage / 2})
	assert_true(bool(out.get("ok", false)), "the split loan did not seal")
	var loan := MarketLoanRecords.load(str(out.get("loan", "")))
	assert_eq(int(loan.get("wage_parent", 0)) + int(loan.get("wage_loanee", 0)), wage,
		"the shares do not sum to the wage")
	assert_eq(int(loan.get("wage_loanee", 0)), wage / 2, "the loanee's share is wrong")


func test_the_caps_refuse_the_seventh_out() -> void:
	var season := _fresh("Loan Caps Out")
	var parent := _club_in("PL", 0)
	var squad := PLDatabase.rows(
		"SELECT id FROM player WHERE club_id = ? ORDER BY id LIMIT 7;", [parent])
	assert_gte(squad.size(), 7, "the parent has too few players for the out-cap test")
	var lent := 0
	for i in range(6):
		var loanee := _club_in("PL", i + 1)
		if bool(_loan(season, parent, loanee, str(squad[i]["id"])).get("ok", false)):
			lent += 1
	assert_eq(lent, 6, "the parent did not lend its six")
	var seventh := MarketLoans.propose(season, parent, _club_in("PL", 7), str(squad[6]["id"]),
		_terms(str(squad[6]["id"])), DATE)
	assert_eq(str(MarketLoans.seal(str(seventh.get("loan", "")), DATE).get("reason", "")),
		"loan_cap_out", "a seventh loan out was allowed")


func test_the_in_cap_refuses_a_seventh_at_the_loanee() -> void:
	var season := _fresh("Loan In Cap")
	var recipient := _club_in("PL", 15)
	var parents: Array = []
	for i in range(7):
		var parent := _club_in("PL", i)
		if parent != recipient:
			parents.append(parent)
	var taken := 0
	for i in range(6):
		var parent := str(parents[i])
		var out := _loan(season, parent, recipient, _player_at(parent))
		if bool(out.get("ok", false)):
			taken += 1
	assert_eq(taken, 6, "the loanee did not take its six")
	var extra := str(parents[6])
	var seventh := MarketLoans.propose(season, extra, recipient, _player_at(extra),
		_terms(_player_at(extra)), DATE)
	assert_eq(str(MarketLoans.seal(str(seventh.get("loan", "")), DATE).get("reason", "")),
		"loan_cap_in", "a seventh loan in was allowed")


func test_the_pair_cap_refuses_a_third_from_one_club() -> void:
	var season := _fresh("Loan Pair")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var squad := PLDatabase.rows(
		"SELECT id FROM player WHERE club_id = ? ORDER BY id LIMIT 4;", [parent])
	var accepted := 0
	for i in range(2):
		if bool(_loan(season, parent, loanee, str(squad[i]["id"])).get("ok", false)):
			accepted += 1
	assert_eq(accepted, 2, "the pair's first two loans did not land")
	var third := MarketLoans.propose(season, parent, loanee, str(squad[2]["id"]),
		_terms(str(squad[2]["id"])), DATE)
	var refused := MarketLoans.seal(str(third.get("loan", "")), DATE)
	assert_eq(str(refused.get("reason", "")), MarketLoanRules.CAP_PAIR,
		"a third loan from one club was allowed")


func test_a_closed_window_refuses_the_loan() -> void:
	var season := _fresh("Loan Window")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var proposed := MarketLoans.propose(season, parent, loanee, player, _terms(player), CLOSED)
	var refused := MarketLoans.seal(str(proposed.get("loan", "")), CLOSED)
	assert_eq(str(refused.get("reason", "")), "window_closed", "a closed window loaned")
	assert_eq(_player_club(player), parent, "a refused loan moved the player")


func test_an_appearance_trigger_converts_through_the_permanent_path() -> void:
	var season := _fresh("Loan Trigger")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var out := _loan(season, parent, loanee, player, {
		"option_kind": "obligation", "buy_fee": 3_000_000,
		"trigger_kind": "appearances_n", "trigger_value": "10"})
	assert_true(bool(out.get("ok", false)), "the obligation loan did not seal")
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_player_stat (player_id, competition_id, club_id, "
		+ "season_index, apps, goals) VALUES (?, 'PL', ?, 0, 10, 2);", [player, loanee])
	var fired := MarketLoans.fire_obligations(season, "2026-10-01")
	assert_eq(fired, 1, "the appearance trigger did not fire")
	var loan := MarketLoanRecords.load(str(out.get("loan", "")))
	assert_eq(str(loan.get("status", "")), MarketLoanRecords.CONVERTED, "the loan did not convert")
	assert_eq(_player_club(player), loanee, "the permanent move did not land")
	var deal := MarketDealRecords.load(str(loan.get("deal_id", "")))
	assert_eq(str(deal.get("state", "")), MarketDealRecords.SIGNED, "the buying deal did not sign")
	assert_eq(str(deal.get("kind", "")), "loan_converted", "the deal is not a converted loan")


func test_a_season_end_trigger_converts_and_return_writes_history() -> void:
	var season := _fresh("Loan Return")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var plain := _loan(season, parent, loanee, player)
	assert_true(bool(plain.get("ok", false)), "the plain loan did not seal")
	var returned := MarketLoans.return_loan(str(plain.get("loan", "")), "2027-05-31")
	assert_eq(str(returned.get("state", "")), MarketLoanRecords.RETURNED, "the loan did not return")
	assert_eq(_player_club(player), parent, "the return did not restore player.club_id")
	assert_eq(str(MarketDealRecords.active_contract(player).get("club_id", "")), parent,
		"the return moved the contract")
	var spell := PLDatabase.row(
		"SELECT to_date FROM player_history WHERE player_id = ? AND club_id = ? AND kind = 'loan';",
		[player, loanee])
	assert_eq(str(spell.get("to_date", "")), "2027-05-31", "the return wrote no history")


func test_a_loan_returns_after_the_loanee_s_last_fixture() -> void:
	var season := _fresh("Loan Fixtures")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var out := _loan(season, parent, loanee, player)
	assert_true(bool(out.get("ok", false)), "the loan did not seal")
	var last := str(PLDatabase.row(
		"SELECT MAX(kickoff) AS d FROM league_fixture WHERE home_club_id = ? OR away_club_id = ?;",
		[loanee, loanee]).get("d", ""))
	assert_true(last != "", "the loanee has no fixture")
	var reviewed := MarketLoans.review(season, last)
	assert_eq(int(reviewed.get("returned", 0)), 1, "the loan did not return after the last fixture")
	assert_eq(_player_club(player), parent, "the loanee kept him past his last fixture")


func test_an_obligation_with_negative_cash_still_commits() -> void:
	var season := _fresh("Loan Debt")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var out := _loan(season, parent, loanee, player, {
		"option_kind": "obligation", "buy_fee": 2_000_000,
		"trigger_kind": "season_end", "trigger_value": ""})
	assert_true(bool(out.get("ok", false)), "the season-end obligation loan did not seal")
	PLDatabase.execute("UPDATE club_finance SET cash = -1 WHERE club_id = ?;", [loanee])
	PLDatabase.execute("UPDATE league_fixture SET status = 'played' WHERE status <> 'played';")
	var fired := MarketLoans.fire_obligations(season, "2027-05-24")
	assert_eq(fired, 1, "the obligation did not fire with the loanee in debt")
	assert_eq(_player_club(player), loanee, "the debt blocked the obligation")
	assert_lt(MarketFinance.cash(loanee), 0, "the deal did not let the cash go negative")


func test_the_isolation_holds_without_the_ai_or_news_module() -> void:
	var season := _fresh("Loan Isolation")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var out := _loan(season, parent, loanee, player)
	assert_true(bool(out.get("ok", false)), "the loan did not seal")
	assert_eq(int(out.get("wage_parent", 0)) + int(out.get("wage_loanee", 0)),
		int(MarketDealRecords.active_contract(player).get("wage", 0)),
		"the sealed loan does not read back its split")
	assert_true(not MarketLoans.due(season, DATE).has(str(out.get("loan", ""))),
		"a fresh loan is already due")


func test_the_player_page_reads_the_loan() -> void:
	var season := _fresh("Loan Page")
	var parent := _club_in("PL", 0)
	var loanee := _club_in("PL", 1)
	var player := _player_at(parent)
	var out := _loan(season, parent, loanee, player, {"option_kind": "option", "buy_fee": 1_000_000})
	assert_true(bool(out.get("ok", false)), "the option loan did not seal")
	var blocks := WikiPlayer.loan_blocks(player)
	assert_false(blocks.is_empty(), "the player page has no loan block")
	var items := _items(blocks)
	assert_eq(str(items.get("PARENT", "")).to_upper(),
		str(WikiModel.repo().club(parent).get("name", "")).to_upper(), "the page names the wrong parent")
	assert_eq(str(items.get("BUY", "")).begins_with("OPTION"), true, "the buy term is wrong")


func _items(blocks: Array) -> Dictionary:
	var out := {}
	for block in blocks:
		var row: Dictionary = block
		if str(row.get("k", "")) != "kv":
			continue
		for item in row.get("items", []):
			var pair: Array = item
			out[str(pair[0])] = pair[1]
	return out


func test_the_engine_refuses_an_empty_loan() -> void:
	var season := _fresh("Loan Empty")
	assert_eq(str(MarketLoans.seal("", DATE).get("reason", "")), "no_loan", "an empty loan sealed")
	assert_eq(str(MarketLoans.return_loan("", DATE).get("reason", "")), "no_loan",
		"an empty loan returned")
	assert_eq(str(MarketLoans.buy("", DATE).get("reason", "")), "no_loan", "an empty loan bought")
	assert_eq(str(MarketLoans.propose(season, "", "", "", {}, DATE).get("reason", "")),
		MarketLoanRules.TERMS, "an empty loan was written")
	assert_true(MarketLoanRecords.load("").is_empty(), "an empty loan loaded a row")
	assert_false(MarketLoanRecords.update("", {"fee": 1}), "an empty loan updated")
	assert_true(MarketLoanRecords.active_for("").is_empty(), "an empty player held a loan")


func test_the_loan_verb_runs_without_the_ai_or_news_module() -> void:
	var verb: Script = load("res://tools/market_sim/loan.gd")
	var out: Dictionary = verb.run({"seed": "7045", "trigger": "appearances_n=10"})
	assert_true(bool(out.get("ok", false)), "the loan verb did not settle: %s" % str(out))
	assert_true(bool(out.get("split_ok", false)), "the verb's split did not sum to the wage")
	assert_eq(int(out.get("fired", 0)), 1, "the verb did not fire the appearance obligation")
