extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_deals_444")
var CACHE_DIR := TestScratch.dir("cache_market_deals_444")
const SEED := 7004

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


func _fresh(name: String, competitions: Array = ["PL"]) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, competitions, false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	return season


func _pair() -> Array:
	var rows := PLDatabase.rows(
		"SELECT id FROM club WHERE competition_id = 'PL' AND stub = 0 ORDER BY name LIMIT 2;")
	assert_eq(rows.size(), 2, "the save has no pair of league clubs")
	return [str(rows[0]["id"]), str(rows[1]["id"])]


func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[club_id]).get("id", ""))


func _offer(season: LeagueSeason, from_club: String, to_club: String, player_id: String,
		extra: Dictionary = {}) -> Dictionary:
	var offer := {
		"player_id": player_id, "from_club_id": from_club, "to_club_id": to_club,
		"kind": "permanent", "fee": 5000000, "wage": 50000, "years": 3, "consent": 1,
		"date": season.save.current_date(),
	}
	offer.merge(extra, true)
	return offer


func _stage(season: LeagueSeason, offer: Dictionary) -> String:
	var made := MarketDeals.propose(season.save, offer)
	var deal_id := str(made.get("deal_id", ""))
	assert_true(deal_id != "", "the deal was not proposed: %s" % str(made.get("reason", "")))
	if deal_id == "":
		return ""
	MarketDeals.negotiate(season.save, deal_id)
	MarketDeals.agree(season.save, deal_id)
	return deal_id


func _sign(season: LeagueSeason, deal_id: String, options: Dictionary = {}) -> Dictionary:
	var opts := options.duplicate(true)
	if not opts.has("date"):
		opts["date"] = str(MarketDeals.one(deal_id).get("created_on", season.save.current_date()))
	return MarketDeals.sign(season.save, deal_id, opts)


func _run(season: LeagueSeason, offer: Dictionary, options: Dictionary = {}) -> Dictionary:
	var deal_id := _stage(season, offer)
	if deal_id == "":
		return {"ok": false, "reason": "not_proposed"}
	return _sign(season, deal_id, options)


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func _contract(player_id: String) -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM player_contract WHERE player_id = ? AND status = 'active';", [player_id])


func _registration(player_id: String, club_id: String) -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM player_registration WHERE player_id = ? AND club_id = ? "
		+ "ORDER BY from_date DESC LIMIT 1;", [player_id, club_id])


func _ledger_rows() -> int:
	return _count("SELECT COUNT(*) AS n FROM club_ledger;")


func _market_day() -> String:
	return str(PLDatabase.row(
		"SELECT value FROM save_meta WHERE key = 'market_day';").get("value", ""))


func _block_items(page: Dictionary) -> Dictionary:
	var found := {}
	var wanted := false
	for block in page.get("blocks", []):
		var entry: Dictionary = block
		if str(entry.get("k", "")) == "section" and str(entry.get("text", "")) == "TRANSFER":
			wanted = true
			continue
		if wanted and str(entry.get("k", "")) == "kv":
			for item in entry.get("items", []):
				found[str((item as Array)[0])] = (item as Array)[1]
			return found
		if wanted:
			break
	return found


func test_a_signed_deal_writes_contract_registration_and_money() -> void:
	var season := _fresh("Deal Happy")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var buyer_cash := MarketFinance.cash(to_club)
	var seller_cash := MarketFinance.cash(from_club)
	var ledger_before := _ledger_rows()
	var deal_id := _stage(season, _offer(season, from_club, to_club, player_id))
	var result := _sign(season, deal_id)
	assert_true(bool(result.get("ok", false)), "the deal did not sign")
	assert_eq(str(result.get("state", "")), MarketDealRecords.SIGNED, "the deal is not signed")
	assert_eq(str(result.get("registration", "")), MarketDealRecords.REGISTERED,
		"the deal registered nothing")
	assert_eq(MarketFinance.cash(to_club), buyer_cash - 5000000, "the buyer did not pay")
	assert_eq(MarketFinance.cash(from_club), seller_cash + 5000000, "the seller was not paid")
	assert_eq(_ledger_rows(), ledger_before + 2, "the fee is not two ledger rows")
	var player := PLDatabase.row("SELECT club_id, number FROM player WHERE id = ?;", [player_id])
	assert_eq(str(player.get("club_id", "")), to_club, "the player did not move")
	var contract := _contract(player_id)
	assert_eq(str(contract.get("club_id", "")), to_club, "the contract is not at the buyer")
	assert_eq(str(contract.get("deal_id", "")), deal_id, "the contract names no deal")
	var old := PLDatabase.row(
		"SELECT status FROM player_contract WHERE player_id = ? AND club_id = ? "
		+ "ORDER BY start_date DESC LIMIT 1;", [player_id, from_club])
	assert_eq(str(old.get("status", "")), "transferred", "the old contract stayed active")
	var registration := _registration(player_id, to_club)
	assert_eq(str(registration.get("state", "")), MarketDealRecords.REGISTERED,
		"the buyer holds no registration")
	assert_eq(str(registration.get("kind", "")), MarketDealRecords.KIND_PERMANENT,
		"the registration lost its kind")
	assert_eq(_market_day(), season.save.current_date(), "the market day was not stamped")
	var history := PLDatabase.row(
		"SELECT * FROM player_history WHERE player_id = ? AND kind = 'transfer';", [player_id])
	assert_false(history.is_empty(), "the move appended no history")
	assert_gte(MarketDeals.timeline(deal_id).size(), 4, "the deal kept no timeline")


func test_the_window_validator_refuses_a_closed_date() -> void:
	var season := _fresh("Deal Window")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var cash := MarketFinance.cash(to_club)
	var deal_id := _stage(season, _offer(season, from_club, to_club, player_id))
	var result := _sign(season, deal_id, {"date": "2026-10-15"})
	assert_false(bool(result.get("ok", false)), "a closed window signed a fee deal")
	assert_eq(str(result.get("state", "")), MarketDealRecords.FAILED, "the deal did not fail")
	assert_eq(str(result.get("reason", "")), MarketDealRecords.WINDOW_CLOSED,
		"the window validator named no reason")
	assert_eq(MarketFinance.cash(to_club), cash, "a refused window moved money")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_contract WHERE deal_id = ?;", [deal_id]), 0,
		"a refused window wrote a contract")


func test_the_player_must_still_be_at_the_from_club() -> void:
	var season := _fresh("Deal At Club")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var deal_id := _stage(season, _offer(season, from_club, to_club, player_id))
	PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [to_club, player_id])
	var result := _sign(season, deal_id)
	assert_false(bool(result.get("ok", false)), "a moved player still signed")
	assert_eq(str(result.get("reason", "")), MarketDealRecords.NOT_AT_CLUB,
		"the player validator named no reason")
	assert_eq(_count("SELECT COUNT(*) AS n FROM club_ledger;"), 0,
		"a stale deal moved money")


func test_a_second_live_deal_is_refused() -> void:
	var season := _fresh("Deal Live")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var first := _stage(season, _offer(season, from_club, to_club, player_id))
	var second := _stage(season, _offer(season, from_club, to_club, player_id))
	assert_true(first != "" and second != "", "the two deals were not proposed")
	var result := _sign(season, second)
	assert_false(bool(result.get("ok", false)), "a second live deal signed")
	assert_eq(str(result.get("reason", "")), MarketDealRecords.LIVE_DEAL,
		"the live-deal validator named no reason")
	assert_eq(str(MarketDeals.one(first).get("state", "")), MarketDealRecords.AGREED,
		"the first deal was disturbed")


func test_incomplete_terms_are_refused() -> void:
	var season := _fresh("Deal Terms")
	var pair := _pair()
	var deal_id := _stage(season, _offer(season, str(pair[0]), str(pair[1]),
		_player_at(str(pair[0])), {"wage": 0}))
	var result := _sign(season, deal_id)
	assert_eq(str(result.get("reason", "")), MarketDealRecords.TERMS_INCOMPLETE,
		"the terms validator named no reason")
	assert_eq(_ledger_rows(), 0, "an incomplete deal moved money")


func test_consent_is_required() -> void:
	var season := _fresh("Deal Consent")
	var pair := _pair()
	var deal_id := _stage(season, _offer(season, str(pair[0]), str(pair[1]),
		_player_at(str(pair[0])), {"consent": 0}))
	var result := _sign(season, deal_id)
	assert_eq(str(result.get("reason", "")), MarketDealRecords.REFUSED_CONSENT,
		"the consent validator named no reason")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_contract WHERE deal_id = ?;", [deal_id]), 0,
		"a refused consent wrote a contract")


func test_the_buying_club_must_hold_the_cash() -> void:
	var season := _fresh("Deal Cash")
	var pair := _pair()
	var to_club := str(pair[1])
	var fee := MarketFinance.cash(to_club) + 1
	var deal_id := _stage(season, _offer(season, str(pair[0]), to_club,
		_player_at(str(pair[0])), {"fee": fee}))
	var result := _sign(season, deal_id)
	assert_eq(str(result.get("reason", "")), MarketDealRecords.NO_CASH,
		"the cash validator named no reason")
	assert_eq(MarketFinance.cash(to_club), fee - 1, "an unaffordable deal moved cash")


func test_the_ffp_validator_returns_its_own_code() -> void:
	var season := _fresh("Deal FFP")
	var pair := _pair()
	var deal_id := _stage(season, _offer(season, str(pair[0]), str(pair[1]),
		_player_at(str(pair[0]))))
	var result := _sign(season, deal_id, {"inject": "ffp"})
	assert_eq(str(result.get("reason", "")), MarketDealRecords.FFP,
		"the FFP validator named no reason")
	assert_eq(_ledger_rows(), 0, "an FFP refusal moved money")


func test_each_validator_reports_its_reason_code() -> void:
	var season := _fresh("Deal Reasons")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var cases := {
		"window_closed": MarketDealRecords.WINDOW_CLOSED,
		"not_at_club": MarketDealRecords.NOT_AT_CLUB,
		"live_deal": MarketDealRecords.LIVE_DEAL,
		"terms": MarketDealRecords.TERMS_INCOMPLETE,
		"consent": MarketDealRecords.REFUSED_CONSENT,
		"cash": MarketDealRecords.NO_CASH,
		"ffp": MarketDealRecords.FFP,
		"clearance": MarketDealRecords.NO_CLEARANCE,
	}
	for inject in cases:
		var deal_id := _stage(season, _offer(season, from_club, to_club, player_id))
		var result := _sign(season, deal_id, {"inject": inject})
		assert_eq(str(result.get("reason", "")), str(cases[inject]),
			"the %s validator named no reason" % inject)
		assert_eq(str(result.get("state", "")), MarketDealRecords.FAILED,
			"the %s refusal did not fail the deal" % inject)


func test_a_free_agent_cannot_carry_a_fee() -> void:
	var season := _fresh("Deal Free Agent Fee")
	var pair := _pair()
	var to_club := str(pair[1])
	var player_id := _player_at(str(pair[0]))
	PLDatabase.execute("UPDATE player SET club_id = '' WHERE id = ?;", [player_id])
	PLDatabase.execute(
		"UPDATE player_contract SET status = 'expired' WHERE player_id = ? AND status = 'active';",
		[player_id])
	var deal_id := _stage(season, _offer(season, "", to_club, player_id, {"fee": 1}))
	var result := _sign(season, deal_id)
	assert_eq(str(result.get("reason", "")), MarketDealRecords.TERMS_INCOMPLETE,
		"a free agent was permitted a fee")


func test_a_refused_list_signs_the_player_ineligible() -> void:
	var season := _fresh("Deal List")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var cash := MarketFinance.cash(to_club)
	var deal_id := _stage(season, _offer(season, from_club, to_club, player_id))
	var result := _sign(season, deal_id, {"inject": "registration"})
	assert_true(bool(result.get("ok", false)), "a refused list voided the deal")
	assert_eq(str(result.get("state", "")), MarketDealRecords.SIGNED,
		"a refused list did not stay signed")
	assert_eq(str(result.get("registration", "")), MarketDealRecords.INELIGIBLE,
		"the player was not marked ineligible")
	assert_eq(MarketFinance.cash(to_club), cash - 5000000, "the fee did not move")
	assert_false(_contract(player_id).is_empty(), "a signed player holds no contract")
	var registration := _registration(player_id, to_club)
	assert_eq(str(registration.get("state", "")), MarketDealRecords.INELIGIBLE,
		"the registration row is not ineligible")
	assert_eq(str(registration.get("reason", "")), MarketDealRecords.LIST_REFUSED,
		"the registration carries no reason")


func test_a_failed_clearance_moves_nothing() -> void:
	var season := _fresh("Deal Clearance")
	var pair := _pair()
	var to_club := str(pair[0])
	var from_club := "ESP-ALA1"
	var player_id := _player_at(from_club)
	var cash := MarketFinance.cash(to_club)
	var ledger_before := _ledger_rows()
	var contracts_before := _count("SELECT COUNT(*) AS n FROM player_contract;")
	var deal_id := _stage(season, _offer(season, from_club, to_club, player_id, {"fee": 500000}))
	var result := _sign(season, deal_id, {"inject": "clearance"})
	assert_false(bool(result.get("ok", false)), "a failed clearance signed")
	assert_eq(str(result.get("state", "")), MarketDealRecords.FAILED, "the deal did not fail")
	assert_eq(str(result.get("reason", "")), MarketDealRecords.NO_CLEARANCE,
		"the clearance validator named no reason")
	assert_eq(MarketFinance.cash(to_club), cash, "a failed clearance moved money")
	assert_eq(_ledger_rows(), ledger_before, "a failed clearance wrote a ledger line")
	assert_eq(_count("SELECT COUNT(*) AS n FROM player_contract;"), contracts_before,
		"a failed clearance wrote a contract")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_registration WHERE deal_id = ?;", [deal_id]), 0,
		"a failed clearance wrote a registration")
	var states: Array = []
	for event in MarketDeals.timeline(deal_id):
		states.append(str((event as Dictionary).get("state", "")))
	assert_true(states.has(MarketDealRecords.CLEARANCE_PENDING),
		"the deal never entered clearance")


func test_an_injected_fault_rolls_back_every_write() -> void:
	var season := _fresh("Deal Rollback")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	season.save.put_meta("market_day", "2026-08-01")
	var buyer_cash := MarketFinance.cash(to_club)
	var seller_cash := MarketFinance.cash(from_club)
	var ledger_before := _ledger_rows()
	var contracts_before := _count("SELECT COUNT(*) AS n FROM player_contract;")
	var deal_id := _stage(season, _offer(season, from_club, to_club, player_id))
	var result := _sign(season, deal_id, {"inject": "fault"})
	assert_false(bool(result.get("ok", false)), "an injected fault signed")
	assert_true(bool(result.get("rolled_back", false)), "the fault did not roll back")
	assert_eq(str(result.get("state", "")), MarketDealRecords.AGREED,
		"a rollback left the deal in a terminal state")
	assert_eq(MarketFinance.cash(to_club), buyer_cash, "the rollback kept the buyer's payment")
	assert_eq(MarketFinance.cash(from_club), seller_cash, "the rollback kept the seller's fee")
	assert_eq(_ledger_rows(), ledger_before, "the rollback kept the ledger lines")
	assert_eq(_count("SELECT COUNT(*) AS n FROM player_contract;"), contracts_before,
		"the rollback kept a contract")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_registration WHERE deal_id = ?;", [deal_id]), 0,
		"the rollback kept a registration")
	assert_eq(_market_day(), "2026-08-01", "the rollback did not restore the market day")


func test_force_block_and_rewrite_commit_through_the_engine() -> void:
	var season := _fresh("Deal God")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var blocked_player := _player_at(from_club)
	var blocked_id := _stage(season, _offer(season, from_club, to_club, blocked_player,
		{"fee": 1000000}))
	var blocked := MarketDeals.block(season.save, blocked_id)
	assert_true(bool(blocked.get("ok", false)), "block refused a live deal")
	assert_eq(str(blocked.get("state", "")), MarketDealRecords.BLOCKED, "block did not kill")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_contract WHERE deal_id = ?;", [blocked_id]), 0,
		"block wrote a contract")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_registration WHERE deal_id = ?;", [blocked_id]), 0,
		"block wrote a registration")
	var vetoed := _run(season, _offer(season, from_club, to_club, blocked_player,
		{"fee": 1000000}))
	assert_eq(str(vetoed.get("reason", "")), MarketDealRecords.GOD_BLOCKED,
		"the veto did not survive the window")
	var next_window := _run(season, _offer(season, from_club, to_club, blocked_player,
		{"fee": 1000000, "date": "2027-01-15"}))
	assert_true(bool(next_window.get("ok", false)), "a new window kept the veto")
	var rewrite_player := _player_at(from_club)
	var rewrite_id := _stage(season, _offer(season, from_club, to_club, rewrite_player,
		{"fee": 1000000}))
	var cash := MarketFinance.cash(to_club)
	var rewritten := MarketDeals.rewrite(season.save, rewrite_id, {"fee": 2000000})
	assert_true(bool(rewritten.get("ok", false)), "rewrite did not re-run the pipeline")
	assert_eq(MarketFinance.cash(to_club), cash - 2000000, "rewrite did not use the new terms")
	var withdrawn_id := _stage(season, _offer(season, from_club, to_club,
		_player_at(from_club)))
	var withdrawn := MarketDeals.withdraw(season.save, withdrawn_id)
	assert_true(bool(withdrawn.get("ok", false)), "withdraw refused a live deal")
	assert_eq(str(withdrawn.get("state", "")), MarketDealRecords.WITHDRAWN,
		"withdraw did not close the deal")
	var again := MarketDeals.block(season.save, withdrawn_id)
	assert_false(bool(again.get("ok", false)), "a withdrawn deal accepted a block")
	var forced_player := _player_at(from_club)
	var forced := MarketDeals.force(season.save,
		_offer(season, from_club, to_club, forced_player,
			{"fee": MarketFinance.cash(to_club) + 10000000}))
	assert_true(bool(forced.get("ok", false)), "force could not sign without cash")
	assert_eq(str(forced.get("state", "")), MarketDealRecords.SIGNED, "force did not sign")
	assert_false(_contract(forced_player).is_empty(), "force wrote no contract")


func test_a_mid_season_move_keeps_both_stat_lines() -> void:
	var season := _fresh("Deal Mid Season")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var player_id := _player_at(from_club)
	var index := season.save.season_index()
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_player_stat (player_id, competition_id, club_id, "
		+ "season_index, apps, goals, assists, yellow, red) VALUES (?, 'PL', ?, ?, 10, 4, 2, 1, 0);",
		[player_id, from_club, index])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_absence (player_id, competition_id, club_id, kind, "
		+ "days_left) VALUES (?, 'PL', ?, 'injury', 9);", [player_id, from_club])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_discipline (player_id, competition_id, club_id, yellows) "
		+ "VALUES (?, 'PL', ?, 4);", [player_id, from_club])
	var result := _run(season, _offer(season, from_club, to_club, player_id))
	assert_true(bool(result.get("ok", false)), "the mid-season move did not sign")
	var seller_line := _count(
		"SELECT COUNT(*) AS n FROM league_player_stat WHERE player_id = ? AND club_id = ?;",
		[player_id, from_club])
	assert_eq(seller_line, 1, "the old club's stat line was lost")
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_player_stat (player_id, competition_id, club_id, "
		+ "season_index, apps, goals, assists, yellow, red) VALUES (?, 'PL', ?, ?, 1, 1, 0, 0, 0);",
		[player_id, to_club, index])
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM league_player_stat WHERE player_id = ?;", [player_id]), 2,
		"the mover does not hold a line for each club")
	var absence := PLDatabase.row(
		"SELECT club_id FROM league_absence WHERE player_id = ?;", [player_id])
	assert_eq(str(absence.get("club_id", "")), to_club, "the injury did not re-home")
	var discipline := PLDatabase.row(
		"SELECT club_id FROM league_discipline WHERE player_id = ?;", [player_id])
	assert_eq(str(discipline.get("club_id", "")), to_club, "the suspension did not re-home")
	assert_eq(_count(
		"SELECT COUNT(*) AS n FROM player_history WHERE player_id = ? AND kind = 'transfer';",
		[player_id]), 1, "the move appended no history")


func test_a_mover_keeps_his_shirt_when_it_is_free() -> void:
	var season := _fresh("Deal Shirt Free")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var used := {}
	for row in PLDatabase.rows("SELECT number FROM player WHERE club_id = ?;", [to_club]):
		used[int(row.get("number", 0))] = true
	var number := 0
	for candidate in range(1, 100):
		if not used.has(candidate):
			number = candidate
			break
	assert_true(number > 0, "the buyer has every shirt number")
	var player_id := _player_at(from_club)
	PLDatabase.execute("UPDATE player SET number = ? WHERE id = ?;", [number, player_id])
	var result := _run(season, _offer(season, from_club, to_club, player_id))
	assert_true(bool(result.get("ok", false)), "the deal did not sign")
	var moved := PLDatabase.row("SELECT number FROM player WHERE id = ?;", [player_id])
	assert_eq(int(moved.get("number", -1)), number, "a free shirt number was not kept")


func test_a_mover_takes_the_next_shirt_when_it_is_taken() -> void:
	var season := _fresh("Deal Shirt Taken")
	var pair := _pair()
	var from_club := str(pair[0])
	var to_club := str(pair[1])
	var used := {}
	for row in PLDatabase.rows("SELECT number FROM player WHERE club_id = ?;", [to_club]):
		used[int(row.get("number", 0))] = true
	var player_id := ""
	var number := 0
	for row in PLDatabase.rows(
			"SELECT id, number FROM player WHERE club_id = ? ORDER BY ovr DESC, id;", [from_club]):
		if used.has(int(row.get("number", 0))):
			player_id = str(row["id"])
			number = int(row["number"])
			break
	assert_true(player_id != "", "the two squads share no shirt number")
	var result := _run(season, _offer(season, from_club, to_club, player_id))
	assert_true(bool(result.get("ok", false)), "the deal did not sign")
	var moved := PLDatabase.row("SELECT club_id, number FROM player WHERE id = ?;", [player_id])
	assert_eq(str(moved.get("club_id", "")), to_club, "the player did not move")
	assert_ne(int(moved.get("number", -1)), number, "a taken shirt number was kept")
	assert_false(used.has(int(moved.get("number", -1))), "the mover took a used number")


func test_the_player_page_shows_the_deal_state_and_reason() -> void:
	var season := _fresh("Deal Page")
	var pair := _pair()
	var to_club := str(pair[0])
	var player_id := _player_at("ESP-ALA1")
	var result := _run(season, _offer(season, "ESP-ALA1", to_club, player_id,
		{"fee": 500000}), {"inject": "clearance"})
	assert_false(bool(result.get("ok", false)), "the clearance deal signed")
	PLRepository.shared().invalidate()
	var items := _block_items(WikiPlayer.page(player_id))
	assert_eq(str(items.get("STATE", "")), "FAILED", "the page hides the deal state")
	assert_eq(str(items.get("REASON", "")), "NO_CLEARANCE", "the page hides the reason")


func test_the_isolated_verb_commits_and_rolls_back() -> void:
	var verb: Script = load("res://tools/market_sim/deal.gd")
	assert_not_null(verb, "the deal verb did not load")
	var signed: Dictionary = verb.run({"from": "ENG-ARS1", "to": "ENG-AVL1",
		"fee": "5000000", "seed": "7004"})
	assert_true(bool(signed.get("ok", false)), "the isolated run did not commit")
	assert_eq(str(signed.get("state", "")), MarketDealRecords.SIGNED, "the verb did not sign")
	assert_eq(str(signed.get("registration", "")), MarketDealRecords.REGISTERED,
		"the verb did not register")
	var faulted: Dictionary = verb.run({"from": "ENG-ARS1", "to": "ENG-AVL1",
		"fee": "5000000", "seed": "7004", "inject": "fault"})
	assert_false(bool(faulted.get("ok", false)), "the injected fault signed")
	assert_true(bool(faulted.get("rolled_back", false)), "the verb did not roll back")
	assert_eq(str(faulted.get("state", "")), MarketDealRecords.AGREED,
		"the fault left a terminal deal")
	var cleared: Dictionary = verb.run({"from": "ESP-ALA1", "to": "ENG-ARS1",
		"fee": "500000", "seed": "7004", "inject": "clearance"})
	assert_false(bool(cleared.get("ok", false)), "the clearance failure signed")
	assert_eq(str(cleared.get("reason", "")), MarketDealRecords.NO_CLEARANCE,
		"the verb lost the clearance reason")
	assert_eq(str(cleared.get("registration", "")), "none", "a failed clearance registered")
	var ineligible: Dictionary = verb.run({"from": "ENG-ARS1", "to": "ENG-AVL1",
		"fee": "5000000", "seed": "7004", "inject": "registration"})
	assert_true(bool(ineligible.get("ok", false)), "a refused list voided the deal")
	assert_eq(str(ineligible.get("registration", "")), MarketDealRecords.INELIGIBLE,
		"the verb did not mark the player ineligible")
