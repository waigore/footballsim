class_name MarketLoans
extends RefCounted


static func available() -> bool:
	return MarketLoanRecords.available() and MarketDeals.available()


static func propose(season: LeagueSeason, parent_id: String, loanee_id: String, player_id: String,
		terms: Dictionary, date: String = "") -> Dictionary:
	if parent_id == "" or loanee_id == "" or player_id == "" or not available():
		return {"ok": false, "reason": MarketLoanRules.TERMS}
	var day := str(terms.get("start_date", date))
	var index := 0
	if season != null and season.save != null:
		index = season.save.season_index()
		if day == "":
			day = season.save.current_date()
	if day == "":
		return {"ok": false, "reason": "no_date"}
	var id := loan_id(player_id, day)
	var wage := int(terms.get("wage", 0))
	var loanee_share := clampi(int(terms.get("wage_loanee", wage)), 0, wage)
	var row := {
		"id": id, "player_id": player_id, "parent_club_id": parent_id,
		"loanee_club_id": loanee_id, "season_index": index, "start_date": day,
		"end_date": str(terms.get("end_date", "")),
		"wage_parent": wage - loanee_share,
		"wage_loanee": loanee_share,
		"fee": int(terms.get("fee", 0)), "option_kind": str(terms.get("option_kind", "none")),
		"buy_fee": int(terms.get("buy_fee", 0)),
		"trigger_kind": str(terms.get("trigger_kind", "")),
		"trigger_value": str(terms.get("trigger_value", "")),
		"status": MarketLoanRecords.ACTIVE,
	}
	if not MarketLoanRecords.create(row):
		return {"ok": false, "reason": "could_not_write"}
	return answer(id)


static func seal(loan_id: String, date: String) -> Dictionary:
	var loan := MarketLoanRecords.load(loan_id)
	if loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	if str(loan.get("status", "")) != MarketLoanRecords.ACTIVE:
		return answer(loan_id)
	var verdict := MarketLoanRules.validate(null, str(loan.get("parent_club_id", "")),
		str(loan.get("loanee_club_id", "")), str(loan.get("player_id", "")),
		terms_of(loan), date, loan_id)
	if not bool(verdict.get("ok", false)):
		PLDatabase.execute("DELETE FROM player_loan WHERE id = ?;", [loan_id])
		return {"ok": false, "loan": loan_id, "state": "failed",
			"reason": str(verdict.get("code", MarketLoanRules.TERMS)),
			"detail": str(verdict.get("detail", ""))}
	var split: Dictionary = verdict.get("split", {})
	PLDatabase.transaction("BEGIN TRANSACTION;")
	MarketLoanRecords.update(loan_id, {
		"wage_parent": int(split.get("parent", 0)),
		"wage_loanee": int(split.get("loanee", 0)),
		"start_date": str(verdict.get("start_date", date)),
		"end_date": str(verdict.get("end_date", "")),
	})
	if not MarketLoanRegister.apply(loan):
		PLDatabase.transaction("ROLLBACK;")
		return {"ok": false, "loan": loan_id, "reason": "registration",
			"state": MarketLoanRecords.ACTIVE}
	PLDatabase.transaction("COMMIT;")
	return answer(loan_id)


static func return_loan(loan_id: String, date: String) -> Dictionary:
	var loan := MarketLoanRecords.load(loan_id)
	if loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	if str(loan.get("status", "")) != MarketLoanRecords.ACTIVE:
		return answer(loan_id)
	var player_id := str(loan.get("player_id", ""))
	var parent := str(loan.get("parent_club_id", ""))
	var loanee := str(loan.get("loanee_club_id", ""))
	var index := int(loan.get("season_index", 0))
	PLDatabase.transaction("BEGIN TRANSACTION;")
	MarketLoanRegister.close(player_id, loanee)
	PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [parent, player_id])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_history (player_id, season_index, club_id, competition_id, "
		+ "kind, from_date, to_date) VALUES (?, ?, ?, ?, 'loan', ?, ?);",
		[player_id, index, loanee, MarketLoanRegister.competition_of(loanee),
			str(loan.get("start_date", "")), date])
	MarketLoanRegister.mark(player_id, parent, index)
	MarketContracts.rehome(player_id, parent)
	MarketLoanRecords.update(loan_id, {"status": MarketLoanRecords.RETURNED, "returned_on": date})
	PLDatabase.transaction("COMMIT;")
	return answer(loan_id)


static func buy(loan_id: String, date: String) -> Dictionary:
	var loan := MarketLoanRecords.load(loan_id)
	if loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	if str(loan.get("status", "")) != MarketLoanRecords.ACTIVE:
		return answer(loan_id)
	var parent := str(loan.get("parent_club_id", ""))
	var loanee := str(loan.get("loanee_club_id", ""))
	var player_id := str(loan.get("player_id", ""))
	var contract := MarketDealRecords.active_contract(player_id)
	var seasons := 4
	var terms := {
		"fee": int(loan.get("buy_fee", 0)),
		"wage": int(contract.get("wage", 0)),
		"years": seasons,
		"agent_fee": 0,
		"signing_bonus": 0,
		"sell_on": 0.0,
		"kind": MarketDeals.PERMANENT,
	}
	var deal := MarketDeals.propose(null, parent, loanee, player_id, terms, date)
	var deal_id := str(deal.get("deal", ""))
	if deal_id == "":
		return {"ok": false, "reason": "no_deal"}
	PLDatabase.execute("UPDATE deal SET kind = 'loan_converted', season_index = ? WHERE id = ?;",
		[int(loan.get("season_index", 0)), deal_id])
	MarketLoanRecords.update(loan_id, {"deal_id": deal_id})
	var agreed := MarketDeals.agree(deal_id, date, {})
	var sealed := MarketDeals.seal(deal_id, date, {})
	if str(sealed.get("state", "")) != MarketDealRecords.SIGNED:
		return {"ok": false, "loan": loan_id, "deal": deal_id,
			"reason": str(sealed.get("reason", ""))}
	MarketLoanRecords.update(loan_id, {"status": MarketLoanRecords.CONVERTED,
		"returned_on": date})
	var out := answer(loan_id)
	out["deal"] = deal_id
	return out


static func due(season: LeagueSeason, date: String) -> Array:
	return MarketLoanObligations.due(season, date)


static func review(season: LeagueSeason, date: String) -> Dictionary:
	return MarketLoanObligations.review(season, date)


static func fire_obligations(season: LeagueSeason, date: String) -> int:
	return MarketLoanObligations.fire(season, date)


static func trigger(loan_id: String, date: String) -> Dictionary:
	return MarketLoanObligations.trigger(loan_id, date)


static func triggered(season: LeagueSeason, loan: Dictionary, date: String) -> bool:
	return MarketLoanObligations.triggered(season, loan, date)


static func answer(loan_id: String) -> Dictionary:
	var loan := MarketLoanRecords.load(loan_id)
	if loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	var status := str(loan.get("status", ""))
	return {
		"ok": status == MarketLoanRecords.ACTIVE or status == MarketLoanRecords.RETURNED
			or status == MarketLoanRecords.CONVERTED,
		"loan": loan_id, "state": status,
		"player": str(loan.get("player_id", "")),
		"parent": str(loan.get("parent_club_id", "")),
		"loanee": str(loan.get("loanee_club_id", "")),
		"wage_parent": int(loan.get("wage_parent", 0)),
		"wage_loanee": int(loan.get("wage_loanee", 0)),
		"end_date": str(loan.get("end_date", "")),
		"option_kind": str(loan.get("option_kind", "none")),
		"buy_fee": int(loan.get("buy_fee", 0)),
		"trigger_kind": str(loan.get("trigger_kind", "")),
	}


static func terms_of(loan: Dictionary) -> Dictionary:
	return {
		"wage": int(loan.get("wage_parent", 0)) + int(loan.get("wage_loanee", 0)),
		"wage_loanee": int(loan.get("wage_loanee", 0)),
		"start_date": str(loan.get("start_date", "")),
		"end_date": str(loan.get("end_date", "")),
		"option_kind": str(loan.get("option_kind", "none")),
		"buy_fee": int(loan.get("buy_fee", 0)),
		"trigger_kind": str(loan.get("trigger_kind", "")),
		"trigger_value": str(loan.get("trigger_value", "")),
	}


static func loan_id(player_id: String, date: String) -> String:
	var count := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_loan WHERE player_id = ? AND start_date = ?;",
		[player_id, date]).get("n", 0))
	return "loan:%s:%s:%d" % [player_id, date, count + 1]
