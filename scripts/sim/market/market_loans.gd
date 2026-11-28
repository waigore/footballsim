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
	if not _register(loan):
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
	_close_registration(player_id, loanee)
	PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [parent, player_id])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_history (player_id, season_index, club_id, competition_id, "
		+ "kind, from_date, to_date) VALUES (?, ?, ?, ?, 'loan', ?, ?);",
		[player_id, index, loanee, _competition_of(loanee), str(loan.get("start_date", "")), date])
	_mark_registered(player_id, parent, index)
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
	var out: Array = []
	if not available() or date == "":
		return out
	for loan in MarketLoanRecords.all_active():
		var end := str(loan.get("end_date", ""))
		if end != "" and date >= end:
			out.append(str(loan.get("id", "")))
			continue
		if _last_fixture_passed(str(loan.get("loanee_club_id", "")), date):
			out.append(str(loan.get("id", "")))
	return out


static func review(season: LeagueSeason, date: String) -> Dictionary:
	var returned := 0
	for loan_id in due(season, date):
		var out := return_loan(str(loan_id), date)
		if str(out.get("state", "")) == MarketLoanRecords.RETURNED:
			returned += 1
	var triggered := fire_obligations(season, date)
	return {"returned": returned, "converted": triggered}


static func fire_obligations(season: LeagueSeason, date: String) -> int:
	var fired := 0
	for loan in MarketLoanRecords.all_active():
		var kind := str(loan.get("trigger_kind", ""))
		if kind == "":
			continue
		if not triggered(season, loan, date):
			continue
		var out := buy(str(loan.get("id", "")), date)
		if str(out.get("state", "")) == MarketLoanRecords.CONVERTED:
			fired += 1
	return fired


static func trigger(loan_id: String, date: String) -> Dictionary:
	var loan := MarketLoanRecords.load(loan_id)
	if loan.is_empty():
		return {"ok": false, "reason": "no_loan"}
	return buy(loan_id, date)


static func triggered(season: LeagueSeason, loan: Dictionary, date: String) -> bool:
	var kind := str(loan.get("trigger_kind", ""))
	if kind == "":
		return false
	var value := str(loan.get("trigger_value", ""))
	var player_id := str(loan.get("player_id", ""))
	var loanee := str(loan.get("loanee_club_id", ""))
	match kind:
		"appearances_n":
			var needed := maxi(int(value), 1)
			var apps := int(PLDatabase.row(
				"SELECT COALESCE(SUM(apps), 0) AS n FROM league_player_stat "
				+ "WHERE player_id = ? AND club_id = ?;", [player_id, loanee]).get("n", 0))
			return apps >= needed
		"club_promoted":
			return _promoted(season, loanee)
		"league_position":
			return _position_met(loanee, int(value))
		"season_end":
			return _season_over(season, date)
	return false


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


static func _register(loan: Dictionary) -> bool:
	var player_id := str(loan.get("player_id", ""))
	var loanee := str(loan.get("loanee_club_id", ""))
	var parent := str(loan.get("parent_club_id", ""))
	var index := int(loan.get("season_index", 0))
	var competition_id := _competition_of(loanee)
	PLDatabase.execute(
		"UPDATE player_registration SET state = 'closed', reason = 'loaned', deal_id = ? "
		+ "WHERE player_id = ? AND club_id = ? AND state <> 'closed';",
		[str(loan.get("id", "")), player_id, parent])
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index) VALUES (?, ?, ?, 'loan', 'registered', '', ?, ?);",
		[player_id, competition_id, loanee, str(loan.get("id", "")), index]) \
		and PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [loanee, player_id]) \
		and MarketContracts.rehome(player_id, loanee) >= 0


static func _close_registration(player_id: String, club_id: String) -> void:
	PLDatabase.execute(
		"UPDATE player_registration SET state = 'closed', reason = 'returned' "
		+ "WHERE player_id = ? AND club_id = ? AND state <> 'closed';", [player_id, club_id])


static func _mark_registered(player_id: String, club_id: String, index: int) -> void:
	var competition_id := _competition_of(club_id)
	if competition_id == "":
		return
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index) VALUES (?, ?, ?, 'permanent', 'registered', '', "
		+ "'', ?);", [player_id, competition_id, club_id, index])


static func _competition_of(club_id: String) -> String:
	return str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[club_id]).get("competition_id", ""))


static func _last_fixture_passed(loanee_club_id: String, date: String) -> bool:
	if loanee_club_id == "":
		return false
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE (home_club_id = ? OR away_club_id = ?) "
		+ "AND status <> 'played' AND kickoff > ?;",
		[loanee_club_id, loanee_club_id, date])
	if int(row.get("n", 0)) > 0:
		return false
	var any := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE home_club_id = ? OR away_club_id = ?;",
		[loanee_club_id, loanee_club_id])
	return int(any.get("n", 0)) > 0


static func _promoted(season: LeagueSeason, club_id: String) -> bool:
	if season == null or season.record == null or season.save == null:
		return false
	var payload := SeasonSettle.stored_payload(season)
	for key in ["pyramid", "promotion"]:
		var part: Dictionary = payload.get(key, {})
		if part.is_empty():
			continue
		for entry in part.get("to_top", []):
			if str(entry) == club_id:
				return true
		for entry in part.get("links", []):
			if (entry as Dictionary).get("to_top", []).has(club_id):
				return true
	return false


static func _position_met(club_id: String, wanted: int) -> bool:
	if wanted <= 0:
		return false
	var competition_id := _competition_of(club_id)
	if competition_id == "":
		return false
	var table: Array = LeagueLedger.table(competition_id)
	for i in range(table.size()):
		if str((table[i] as Dictionary).get("club_id", "")) == club_id:
			return i + 1 <= wanted
	return false


static func _season_over(season: LeagueSeason, date: String) -> bool:
	if season == null or season.record == null:
		return false
	if season.record.fixtures.unplayed() == 0:
		return true
	if season.save == null:
		return false
	var end := str(season.save.rules.get("season_end", ""))
	return end != "" and date >= end
