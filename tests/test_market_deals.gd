extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_deals_444")
var CACHE_DIR := TestScratch.dir("cache_market_deals_444")
const SEED := 6150
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
	assert_true(bool(MarketWindows.state(DATE, "ENG").get("open", false)),
		"the summer window is not open on %s" % DATE)
	assert_false(bool(MarketWindows.state(CLOSED, "ENG").get("open", false)),
		"the window is open on %s" % CLOSED)
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


func _player_club(player_id: String) -> String:
	return str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player_id]).get("club_id", ""))


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func _ledger_lines() -> int:
	return _count("SELECT COUNT(*) AS n FROM club_ledger;")


func _market_day() -> String:
	return str(PLDatabase.row("SELECT value FROM save_meta WHERE key = 'market_day';").get(
		"value", ""))


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
	var out := MarketDeals.propose(season.save, from, to, player, terms, date)
	assert_true(str(out.get("deal", "")) != "", "the deal was not proposed")
	return str(out.get("deal", ""))


func test_an_open_window_signs_a_domestic_deal() -> void:
	var season := _fresh("Deal Sign")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var cash_from := MarketFinance.cash(from)
	var cash_to := MarketFinance.cash(to)
	var deal := _propose(season, from, to, player, _terms(player))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.AGREED,
		"the deal was not agreed: %s" % str(agreed.get("reason", "")))
	var done := MarketDeals.seal(deal, DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"the deal did not sign: %s" % str(done.get("reason", "")))
	assert_eq(str(done.get("registration", "")), "registered",
		"the commit module did not report registration")
	assert_eq(_player_club(player), to, "the player did not move")
	assert_eq(MarketFinance.cash(to), cash_to - 5_000_000, "the buyer did not pay the fee")
	assert_eq(MarketFinance.cash(from), cash_from + 5_000_000, "the seller was not paid")
	var contract := MarketDealRecords.active_contract(player)
	assert_eq(str(contract.get("club_id", "")), to, "the contract is not at the buyer")
	assert_eq(int(contract.get("wage", 0)), int(_terms(player)["wage"]), "the wage was not written")
	var registration := MarketDealRecords.registration(player, _competition(to))
	assert_eq(str(registration.get("state", "")), "registered", "the registration is not live")
	assert_gte(_count("SELECT COUNT(*) AS n FROM deal_event WHERE deal_id = ?;", [deal]), 3,
		"the timeline lost its steps")
	assert_eq(_market_day(), DATE, "the market day was not stamped")


func test_a_closed_window_refuses_the_deal() -> void:
	var season := _fresh("Deal Window")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var ledger := _ledger_lines()
	var cash_to := MarketFinance.cash(to)
	var cash_from := MarketFinance.cash(from)
	var deal := _propose(season, from, to, player, _terms(player), CLOSED)
	var agreed := MarketDeals.agree(deal, CLOSED)
	assert_false(bool(agreed.get("ok", false)), "a closed window agreed a deal")
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.FAILED, "the deal stayed live")
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.WINDOW_CLOSED,
		"the refusal does not name the window")
	assert_eq(_ledger_lines(), ledger, "a refused deal wrote a ledger line")
	assert_eq(MarketFinance.cash(to), cash_to, "a refused deal moved the buyer's cash")
	assert_eq(MarketFinance.cash(from), cash_from, "a refused deal moved the seller's cash")


func test_a_player_who_is_not_at_the_club_refuses() -> void:
	var season := _fresh("Deal Club")
	var wrong := _club_in("PL", 1)
	var to := _club_in("PL", 2)
	var player := _player_at(_club_in("PL", 0))
	var agreed := MarketDeals.agree(_propose(season, wrong, to, player, _terms(player)), DATE)
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.NOT_AT_CLUB,
		"the engine moved a player who was not there")
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.FAILED, "the deal stayed live")


func test_a_live_deal_refuses_a_second() -> void:
	var season := _fresh("Deal Live")
	var from := _club_in("PL", 0)
	var player := _player_at(from)
	var first := _propose(season, from, _club_in("PL", 1), player, _terms(player))
	assert_eq(str(MarketDeals.agree(first, DATE).get("state", "")), MarketDealRecords.AGREED,
		"the first deal did not agree")
	var second := _propose(season, from, _club_in("PL", 2), player, _terms(player))
	var agreed := MarketDeals.agree(second, DATE)
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.LIVE_DEAL,
		"two live deals were allowed")
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.FAILED, "the second deal stayed live")


func test_incomplete_terms_refuse() -> void:
	var season := _fresh("Deal Terms")
	var from := _club_in("PL", 0)
	var player := _player_at(from)
	var agreed := MarketDeals.agree(
		_propose(season, from, _club_in("PL", 1), player, _terms(player, {"wage": 0})), DATE)
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.TERMS,
		"a wage-less deal was allowed")


func test_a_pay_cut_needs_consent_and_god_can_force_it() -> void:
	var season := _fresh("Deal Consent")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 0))
	var cut := _terms(player, {"wage": maxi(wage - 1000, 1)})
	var refused := MarketDeals.agree(_propose(season, from, to, player, cut), DATE)
	assert_eq(str(refused.get("reason", "")), MarketDealRules.CONSENT,
		"a pay cut signed without consent")
	var forced := MarketDeals.force(_propose(season, from, to, player, cut), DATE)
	assert_eq(str(forced.get("state", "")), MarketDealRecords.SIGNED,
		"god could not force the deal: %s" % str(forced.get("reason", "")))
	assert_eq(_player_club(player), to, "a forced deal did not move the player")


func test_cash_refuses_a_deal_the_buyer_cannot_pay() -> void:
	var season := _fresh("Deal Cash")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var fee := MarketFinance.cash(to) + 1_000_000
	var ledger := _ledger_lines()
	var agreed := MarketDeals.agree(_propose(season, from, to, player,
		_terms(player, {"fee": fee})), DATE)
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.NO_CASH,
		"the engine spent money the buyer does not hold")
	assert_eq(_ledger_lines(), ledger, "a refused deal wrote a ledger line")


func test_ffp_refuses_a_deal_over_the_headroom() -> void:
	var season := _fresh("Deal FFP")
	var buyer := ""
	var fee := 0
	var seller := _club_in("PL", 0)
	for club in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;"):
		var club_id := str(club["id"])
		if club_id == seller:
			continue
		var player := _player_at(seller)
		var wage := int(MarketDealRecords.active_contract(player).get("wage", 0))
		var over := MarketFinance.ffp_headroom(club_id) - wage * 52 + 1
		if over > 0 and MarketFinance.can_afford(club_id, over):
			buyer = club_id
			fee = over
			break
	assert_true(buyer != "", "no club was within reach of an FFP breach")
	var agreed := MarketDeals.agree(_propose(season, seller, buyer, _player_at(seller),
		_terms(_player_at(seller), {"fee": fee, "years": 1})), DATE)
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.FFP, "the deal passed its FFP line")
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.FAILED, "the deal stayed live")


func test_the_list_refuses_with_its_own_code() -> void:
	var season := _fresh("Deal List")
	var from := _club_in("PL", 0)
	var player := _player_at(from)
	var agreed := MarketDeals.agree(_propose(season, from, _club_in("PL", 1), player,
		_terms(player)), DATE, {"list": "refuse"})
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.LIST, "the list refusal has no code")


func test_a_failed_clearance_moves_nothing() -> void:
	var season := _fresh("Deal Clearance")
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var ledger := _ledger_lines()
	var cash_to := MarketFinance.cash(to)
	var cash_from := MarketFinance.cash(from)
	var deal := _propose(season, from, to, player, _terms(player, {"fee": 500_000}))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.CLEARANCE_PENDING,
		"an association change did not wait for clearance")
	var failed := MarketDeals.resolve_clearance(deal, str(agreed.get("clears_on", DATE)),
		{"clearance": "fail"})
	assert_eq(str(failed.get("state", "")), MarketDealRecords.FAILED, "a failed clearance signed")
	assert_eq(str(failed.get("reason", "")), MarketDealRules.CLEARANCE,
		"the failure does not name clearance")
	assert_eq(_ledger_lines(), ledger, "a failed clearance wrote a ledger line")
	assert_eq(MarketFinance.cash(to), cash_to, "a failed clearance moved the buyer's cash")
	assert_eq(MarketFinance.cash(from), cash_from, "a failed clearance moved the seller's cash")
	assert_ne(str(MarketDealRecords.active_contract(player).get("club_id", "")), to,
		"a failed clearance wrote a contract")
	assert_eq(_player_club(player), from, "a failed clearance moved the player")


func test_a_refused_registration_leaves_him_ineligible() -> void:
	var season := _fresh("Deal Registration")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var cash_to := MarketFinance.cash(to)
	var deal := _propose(season, from, to, player, _terms(player))
	assert_eq(str(MarketDeals.agree(deal, DATE).get("state", "")), MarketDealRecords.AGREED,
		"the deal did not agree")
	var done := MarketDeals.seal(deal, DATE, {"registration": "refuse"})
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"a refused registration voided the deal: %s" % str(done.get("reason", "")))
	assert_eq(MarketFinance.cash(to), cash_to - 5_000_000, "the fee did not move")
	var registration := MarketDealRecords.registration(player, _competition(to))
	assert_eq(str(registration.get("state", "")), "ineligible",
		"the refused player reads as registered")
	assert_eq(str(registration.get("reason", "")), MarketDealRules.LIST,
		"the registration does not carry its reason")


func test_an_injected_fault_rolls_back_every_write() -> void:
	var season := _fresh("Deal Fault")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var ledger := _ledger_lines()
	var cash_to := MarketFinance.cash(to)
	var cash_from := MarketFinance.cash(from)
	var day := _market_day()
	var deal := _propose(season, from, to, player, _terms(player))
	assert_eq(str(MarketDeals.agree(deal, DATE).get("state", "")), MarketDealRecords.AGREED,
		"the deal did not agree")
	var done := MarketDeals.seal(deal, DATE, {"fault": "contract"})
	assert_false(bool(done.get("ok", true)), "a faulted commit reported success")
	assert_true(bool(done.get("rolled_back", false)), "the fault did not roll back")
	assert_eq(_ledger_lines(), ledger, "the rolled-back commit left a ledger line")
	assert_eq(MarketFinance.cash(to), cash_to, "the rolled-back commit moved the buyer's cash")
	assert_eq(MarketFinance.cash(from), cash_from, "the rolled-back commit moved the seller's cash")
	assert_eq(_market_day(), day, "the rolled-back commit stamped the market day")
	assert_ne(str(MarketDealRecords.active_contract(player).get("club_id", "")), to,
		"the rolled-back commit wrote a contract")
	assert_eq(str(MarketDealRecords.load(deal).get("state", "")), MarketDealRecords.AGREED,
		"the rolled-back deal lost its state")


func test_a_mid_season_move_keeps_the_old_line_and_the_history() -> void:
	var season := _fresh("Deal History")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_player_stat (player_id, competition_id, club_id, "
		+ "season_index, apps, goals) VALUES (?, 'PL', ?, 0, 7, 3);", [player, from])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_absence (player_id, competition_id, club_id, kind, "
		+ "grade, days_left) VALUES (?, 'PL', ?, 'injury', 'knock', 4);", [player, from])
	var deal := _propose(season, from, to, player, _terms(player))
	MarketDeals.agree(deal, DATE)
	var done := MarketDeals.seal(deal, DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the move did not sign")
	var old := PLDatabase.row(
		"SELECT apps, goals FROM league_player_stat WHERE player_id = ? AND club_id = ?;",
		[player, from])
	assert_eq(int(old.get("apps", 0)), 7, "the old club's stat line was dropped")
	var absence := PLDatabase.row(
		"SELECT club_id FROM league_absence WHERE player_id = ?;", [player])
	assert_eq(str(absence.get("club_id", "")), to, "the injury did not re-home")
	var spell := PLDatabase.row(
		"SELECT to_date FROM player_history WHERE player_id = ? AND club_id = ? AND kind = 'spell';",
		[player, from])
	assert_eq(str(spell.get("to_date", "")), DATE, "the history row was not written")


func test_a_mover_keeps_his_number_when_it_is_free() -> void:
	var season := _fresh("Deal Number")
	var pair := _number_pair()
	var from := str(pair.get("from", ""))
	var to := str(pair.get("to", ""))
	var keeper := str(pair.get("keeper", ""))
	var mover := str(pair.get("mover", ""))
	assert_true(from != "" and keeper != "" and mover != "", "the number test found no pair")
	var keep_number := int(PLDatabase.row("SELECT number FROM player WHERE id = ?;", [keeper]).get(
		"number", 0))
	var kept := _seal_player(season, from, to, keeper)
	assert_eq(str(kept.get("state", "")), MarketDealRecords.SIGNED, "the keeper did not move")
	assert_eq(int(PLDatabase.row("SELECT number FROM player WHERE id = ?;", [keeper]).get(
		"number", 0)), keep_number, "the mover lost his free shirt")
	var before := int(PLDatabase.row("SELECT number FROM player WHERE id = ?;", [mover]).get(
		"number", 0))
	var moved := _seal_player(season, from, to, mover)
	assert_eq(str(moved.get("state", "")), MarketDealRecords.SIGNED, "the second mover did not sign")
	var after := int(PLDatabase.row("SELECT number FROM player WHERE id = ?;", [mover]).get(
		"number", 0))
	assert_ne(after, before, "a taken number was not replaced")
	assert_between(after, 1, 99, "the new number is off the shirt list")


func _seal_player(season: LeagueSeason, from: String, to: String, player: String) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player)
	var terms := _terms(player, {"wage": int(contract.get("wage", 1)), "fee": 100_000})
	var deal := _propose(season, from, to, player, terms)
	MarketDeals.agree(deal, DATE)
	return MarketDeals.seal(deal, DATE)


func _number_pair() -> Dictionary:
	var clubs := PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;")
	for i in range(clubs.size()):
		for j in range(clubs.size()):
			if i == j:
				continue
			var from := str(clubs[i]["id"])
			var to := str(clubs[j]["id"])
			var taken := {}
			for row in PLDatabase.rows("SELECT number FROM player WHERE club_id = ?;", [to]):
				taken[int(row["number"])] = true
			var keeper := ""
			var mover := ""
			for row in PLDatabase.rows(
					"SELECT id, number FROM player WHERE club_id = ? ORDER BY number;", [from]):
				if taken.has(int(row["number"])):
					if mover == "":
						mover = str(row["id"])
				elif keeper == "":
					keeper = str(row["id"])
			if keeper != "" and mover != "":
				return {"from": from, "to": to, "keeper": keeper, "mover": mover}
	return {}


func test_god_can_block_a_deal_and_the_engine_keeps_the_veto() -> void:
	var season := _fresh("Deal Block")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	assert_eq(str(MarketDeals.agree(deal, DATE).get("state", "")), MarketDealRecords.AGREED,
		"the deal did not agree")
	var blocked := MarketDeals.block(deal, DATE, "not this window")
	assert_eq(str(blocked.get("state", "")), MarketDealRecords.BLOCKED, "the veto did not land")
	var again := _propose(season, from, to, player, _terms(player))
	var refused := MarketDeals.agree(again, DATE)
	assert_eq(str(refused.get("reason", "")), MarketDealRules.BLOCKED,
		"the engine forgot the veto for this window")
	assert_eq(str(refused.get("state", "")), MarketDealRecords.FAILED, "the vetoed deal stayed live")


func test_the_player_page_reads_the_transfer_block() -> void:
	var season := _fresh("Deal Page")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	MarketDeals.agree(deal, DATE)
	var done := MarketDeals.seal(deal, DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED, "the move did not sign")
	var page := WikiPlayer.page(player)
	var items := _transfer_items(page)
	assert_false(items.is_empty(), "the player page has no transfer block")
	assert_eq(str(items.get("STATE", "")), MarketDealCopy.state(MarketDealRecords.SIGNED),
		"the page does not read the state the deal reached")
	assert_eq(str(items.get("TO", "")).to_upper(),
		str(WikiModel.repo().club(to).get("name", "")).to_upper(), "the page names the wrong buyer")
	var refused_player := _player_at(_club_in("PL", 3))
	var refused := MarketDeals.agree(_propose(season, _club_in("PL", 3), _club_in("PL", 4),
		refused_player, _terms(refused_player)), CLOSED)
	assert_eq(str(refused.get("reason", "")), MarketDealRules.WINDOW_CLOSED, "the deal did not fail")
	var failed_items := _transfer_items(WikiPlayer.page(refused_player))
	assert_eq(str(failed_items.get("REASON", "")), MarketDealCopy.reason(MarketDealRules.WINDOW_CLOSED),
		"the page does not name the reason the deal failed")


func test_the_engine_refuses_a_deal_it_does_not_have() -> void:
	var season := _fresh("Deal Empty")
	assert_eq(str(MarketDeals.negotiate("", DATE).get("reason", "")), "no_deal",
		"an empty deal negotiated")
	assert_eq(str(MarketDeals.agree("", DATE).get("reason", "")), "no_deal", "an empty deal agreed")
	assert_eq(str(MarketDeals.seal("", DATE).get("reason", "")), "no_deal", "an empty deal sealed")
	assert_eq(str(MarketDeals.block("", DATE).get("reason", "")), "no_deal", "an empty deal blocked")
	assert_eq(str(MarketDeals.force("", DATE).get("reason", "")), "no_deal", "an empty deal forced")
	assert_eq(str(MarketDeals.rewrite("", {}, DATE).get("reason", "")), "no_deal",
		"an empty deal was rewritten")
	assert_eq(str(MarketDeals.resolve_clearance("", DATE).get("reason", "")), "no_deal",
		"an empty deal cleared")
	assert_eq(str(MarketDeals.propose(season.save, "", "", "", {}, DATE).get("reason", "")),
		"terms_incomplete", "an empty proposal was written")
	assert_true(MarketDealRecords.load("").is_empty(), "an empty deal loaded a row")
	assert_false(MarketDealRecords.update("", {"fee": 1}), "an empty deal updated")
	assert_false(MarketDealRecords.set_state("", MarketDealRecords.AGREED, DATE),
		"an empty deal changed state")
	assert_false(MarketDealRecords.event("", DATE, MarketDealRecords.AGREED), "an empty event")
	assert_true(MarketDealRecords.events("").is_empty(), "an empty deal listed events")
	assert_true(MarketDealRecords.live_for("").is_empty(), "an empty player had a live deal")
	assert_true(MarketDealRecords.last_for("").is_empty(), "an empty player had a deal")
	assert_false(MarketDealRecords.vetoed("", "", ""), "an empty veto fired")
	assert_true(MarketDealRecords.active_contract("").is_empty(), "an empty player held a contract")
	assert_true(MarketDealRecords.registration("", "").is_empty(), "an empty registration read")


func test_negotiate_rewrite_and_the_timeline() -> void:
	var season := _fresh("Deal Timeline")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	assert_eq(str(MarketDeals.negotiate(deal, DATE).get("state", "")), MarketDealRecords.NEGOTIATING,
		"the deal did not move into talks")
	var rewritten := MarketDeals.rewrite(deal, _terms(player, {"fee": 7_000_000}), DATE)
	assert_eq(str(rewritten.get("state", "")), MarketDealRecords.AGREED,
		"a rewritten deal did not re-run the pipeline")
	assert_eq(int(MarketDealRecords.load(deal).get("fee", 0)), 7_000_000, "the new fee was not kept")
	assert_eq(str(MarketDeals.seal(deal, DATE).get("state", "")), MarketDealRecords.SIGNED,
		"the rewritten deal did not seal")
	assert_eq(str(MarketDeals.seal(deal, DATE).get("state", "")), MarketDealRecords.SIGNED,
		"a repeat seal lost the deal")
	assert_true(bool(MarketDeals.seal(deal, DATE).get("duplicate", false)),
		"a repeat seal was not read as a duplicate")
	var states: Array = []
	for step in MarketDealRecords.events(deal):
		states.append(str(step.get("state", "")))
	assert_in(MarketDealRecords.NEGOTIATING, states, "the timeline lost the talks")
	assert_in(MarketDealRecords.SIGNED, states, "the timeline lost the signing")
	assert_eq(str(MarketDeals.rewrite(deal, _terms(player), DATE).get("state", "")),
		MarketDealRecords.SIGNED, "a signed deal was rewritten")


func test_a_free_agent_signs_outside_the_window() -> void:
	var season := _fresh("Deal Free Agent")
	var to := _club_in("PL", 1)
	var seller := _club_in("PL", 0)
	var player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr LIMIT 1;", [seller]).get("id", ""))
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	PLDatabase.execute("UPDATE player_contract SET status = 'expired' WHERE player_id = ?;",
		[player])
	PLDatabase.execute("UPDATE player SET club_id = '' WHERE id = ?;", [player])
	var terms := {"fee": 0, "wage": wage, "years": 2, "agent_fee": 0, "signing_bonus": 0}
	var deal := _propose(season, "", to, player, terms, CLOSED)
	assert_eq(str(MarketDeals.agree(deal, CLOSED).get("state", "")), MarketDealRecords.AGREED,
		"the free-agent exception did not open the closed window")
	var done := MarketDeals.seal(deal, CLOSED)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"the free agent did not sign: %s" % str(done.get("reason", "")))
	assert_eq(_player_club(player), to, "the free agent did not move")
	var registration := MarketDealRecords.registration(player, _competition(to))
	assert_eq(str(registration.get("state", "")), "registered", "the free agent is not registered")
	assert_eq(_ledger_lines(), 0, "a free signing wrote a fee line")


func _transfer_items(page: Dictionary) -> Dictionary:
	var wanted := false
	for block in page.get("blocks", []):
		var row: Dictionary = block
		if str(row.get("k", "")) == "section" \
				and str(row.get("text", "")) == "TRANSFER":
			wanted = true
			continue
		if wanted and str(row.get("k", "")) == "kv":
			var out := {}
			for item in row.get("items", []):
				var pair: Array = item
				out[str(pair[0])] = pair[1]
			return out
	return {}
