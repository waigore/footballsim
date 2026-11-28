class_name MarketDealCommit
extends RefCounted


static func run(deal: Dictionary, date: String, mode: Dictionary = {}) -> Dictionary:
	var deal_id := str(deal.get("id", ""))
	var buyer := str(deal.get("to_club_id", ""))
	PLDatabase.transaction("BEGIN TRANSACTION;")
	_move_money(deal, date)
	MarketAttribution.apply(deal, date)
	if str(mode.get("fault", "")) == "contract":
		PLDatabase.transaction("ROLLBACK;")
		MarketDealRecords.event(deal_id, date, MarketDealRecords.AGREED, "injected")
		return {"ok": false, "rolled_back": true, "reason": "injected",
			"state": MarketDealRecords.AGREED}
	if not _write_contract(deal, date):
		PLDatabase.transaction("ROLLBACK;")
		return {"ok": false, "rolled_back": true, "reason": "contract",
			"state": MarketDealRecords.AGREED}
	var registration := _write_registration(deal, date, mode)
	_history(deal, date)
	PLDatabase.execute(
		"INSERT OR REPLACE INTO save_meta (key, value) VALUES ('market_day', ?);", [date])
	PLDatabase.transaction("COMMIT;")
	var reason: String = "" if registration == "registered" else MarketDealRules.LIST
	MarketDealRecords.set_state(deal_id, MarketDealRecords.SIGNED, date, reason)
	var out := _answer(deal_id)
	out["registration"] = registration
	out["cash"] = MarketFinance.cash(buyer)
	out["headroom"] = MarketFinance.ffp_headroom(buyer)
	return out


static func _answer(deal_id: String) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	var state := str(deal.get("state", ""))
	return {
		"ok": state == MarketDealRecords.SIGNED,
		"deal": deal_id, "state": state,
		"reason": str(deal.get("reason", "")), "god": str(deal.get("god", "")),
		"player": str(deal.get("player_id", "")), "from": str(deal.get("from_club_id", "")),
		"to": str(deal.get("to_club_id", "")), "fee": int(deal.get("fee", 0)),
		"window_id": str(deal.get("window_id", "")),
		"clears_on": str(deal.get("clears_on", "")),
	}


static func _move_money(deal: Dictionary, date: String) -> void:
	var buyer := str(deal.get("to_club_id", ""))
	var seller := str(deal.get("from_club_id", ""))
	var player_id := str(deal.get("player_id", ""))
	var deal_id := str(deal.get("id", ""))
	var fee := int(deal.get("fee", 0))
	var agent := int(deal.get("agent_fee", 0))
	var bonus := int(deal.get("signing_bonus", 0))
	if fee > 0:
		MarketFinance.post(buyer, date, MarketFinance.KIND_FEE, -fee, seller, player_id, deal_id)
		if seller != "":
			MarketFinance.post(seller, date, MarketFinance.KIND_FEE, fee, buyer, player_id, deal_id)
		MarketFinance.post_amortisation(buyer, date, fee, int(deal.get("years", 1)), player_id)
	if agent > 0:
		MarketFinance.post(buyer, date, MarketFinance.KIND_AGENT, -agent, "", player_id, deal_id)
	if bonus > 0:
		MarketFinance.post(buyer, date, MarketFinance.KIND_AGENT, -bonus, player_id, player_id,
			deal_id)


static func _write_contract(deal: Dictionary, date: String) -> bool:
	var player_id := str(deal.get("player_id", ""))
	var club_id := str(deal.get("to_club_id", ""))
	var years := maxi(int(deal.get("years", 1)), 1)
	var player := PLDatabase.row("SELECT number FROM player WHERE id = ?;", [player_id])
	var old := MarketDealRecords.active_contract(player_id)
	if not old.is_empty():
		PLDatabase.execute(
			"UPDATE player_contract SET status = 'moved' WHERE player_id = ? AND start_date = ?;",
			[player_id, str(old.get("start_date", ""))])
	var end := FixtureCalendar.add_days(FixtureCalendar.add_years(date, years), -1)
	if not PLDatabase.execute(
			"INSERT OR REPLACE INTO player_contract (player_id, club_id, season_index, start_date, "
			+ "end_date, wage, signing_bonus, agent_fee, release_clause, option_years, status, "
			+ "deal_id, declined) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, 0, 'active', ?, 0);",
			[player_id, club_id, int(deal.get("season_index", 0)), date, end,
				int(deal.get("wage", 0)), int(deal.get("signing_bonus", 0)),
				int(deal.get("agent_fee", 0)), str(deal.get("id", ""))]):
		return false
	var number := _number_for(club_id, player_id, int(player.get("number", 0)))
	return PLDatabase.execute("UPDATE player SET club_id = ?, number = ? WHERE id = ?;",
		[club_id, number, player_id])


static func _write_registration(deal: Dictionary, date: String, mode: Dictionary = {}) -> String:
	var player_id := str(deal.get("player_id", ""))
	var buyer := str(deal.get("to_club_id", ""))
	var seller := str(deal.get("from_club_id", ""))
	var club := MarketDealRules.club_row(buyer)
	var competition_id := str(club.get("competition_id", ""))
	var state := SquadList.REGISTERED
	var reason := ""
	if str(mode.get("registration", "")) == "refuse":
		state = SquadList.INELIGIBLE
		reason = MarketDealRules.LIST
	if state == "registered":
		var list := MarketLists.registrable(player_id, buyer, competition_id)
		if not bool(list.get("ok", false)):
			state = "ineligible"
			reason = str(list.get("code", MarketDealRules.LIST))
	if seller != "":
		PLDatabase.execute(
			"UPDATE player_registration SET state = 'closed', reason = 'moved', deal_id = ? "
			+ "WHERE club_id = ? AND player_id = ? AND state <> 'closed';",
			[str(deal.get("id", "")), seller, player_id])
	var kind := str(deal.get("kind", "permanent"))
	SquadList.register(buyer, competition_id, player_id, state, reason,
		str(deal.get("id", "")), int(deal.get("season_index", 0)), kind)
	var refused := state == SquadList.INELIGIBLE
	for listed in SquadList.entries(buyer):
		if str(listed) == competition_id:
			continue
		var ok := bool(SquadList.verdict(buyer, str(listed), player_id).get("ok", true))
		SquadList.register(buyer, str(listed), player_id,
			SquadList.REGISTERED if ok and not refused else SquadList.INELIGIBLE,
			"" if ok and not refused else MarketDealRules.LIST,
			str(deal.get("id", "")), int(deal.get("season_index", 0)), kind)
	return state


static func _history(deal: Dictionary, date: String) -> void:
	var player_id := str(deal.get("player_id", ""))
	var seller := str(deal.get("from_club_id", ""))
	MarketContracts.rehome(player_id, str(deal.get("to_club_id", "")))
	if seller == "":
		return
	var old := PLDatabase.row(
		"SELECT start_date FROM player_contract WHERE club_id = ? AND player_id = ? "
		+ "AND status = 'moved' ORDER BY start_date DESC LIMIT 1;", [seller, player_id])
	var club := MarketDealRules.club_row(seller)
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_history (player_id, season_index, club_id, competition_id, "
		+ "kind, from_date, to_date) VALUES (?, ?, ?, ?, 'spell', ?, ?);",
		[player_id, int(deal.get("season_index", 0)), seller,
			str(club.get("competition_id", "")), str(old.get("start_date", "")), date])


static func _number_for(club_id: String, player_id: String, keep: int) -> int:
	var taken := {}
	for row in PLDatabase.rows("SELECT number FROM player WHERE club_id = ? AND id <> ?;",
			[club_id, player_id]):
		taken[int(row.get("number", 0))] = true
	if keep > 0 and not taken.has(keep):
		return keep
	for number in range(1, 100):
		if not taken.has(number):
			return number
	return maxi(taken.size() + 1, 1)
