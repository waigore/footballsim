class_name MarketDeals
extends RefCounted


const PERMANENT := "permanent"
const LOAN := "loan"


static func available() -> bool:
	return MarketDealRecords.available()


static func propose(season: LeagueSeason, from_club_id: String, to_club_id: String,
		player_id: String, terms: Dictionary, date: String = "") -> Dictionary:
	if player_id == "" or to_club_id == "" or not available():
		return {"ok": false, "reason": "terms_incomplete"}
	var day := date
	var index := 0
	if season != null and season.save != null:
		index = season.save.season_index()
		if day == "":
			day = season.save.current_date()
	if day == "":
		return {"ok": false, "reason": "no_date"}
	var row := {
		"id": MarketDealRecords.next_id(player_id, day),
		"kind": str(terms.get("kind", PERMANENT)),
		"season_index": index,
		"state": MarketDealRecords.PROPOSED,
		"from_club_id": from_club_id,
		"to_club_id": to_club_id,
		"player_id": player_id,
		"fee": int(terms.get("fee", 0)),
		"wage": int(terms.get("wage", 0)),
		"signing_bonus": int(terms.get("signing_bonus", 0)),
		"agent_fee": int(terms.get("agent_fee", 0)),
		"years": int(terms.get("years", 1)),
		"sell_on": float(terms.get("sell_on", 0.0)),
		"opened_on": day,
		"deal_terms": JSON.stringify(terms),
	}
	if not MarketDealRecords.create(row):
		return {"ok": false, "reason": "could_not_write"}
	MarketDealRecords.event(str(row["id"]), day, MarketDealRecords.PROPOSED, "")
	return answer(str(row["id"]))


static func negotiate(deal_id: String, date: String) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	if str(deal.get("state", "")) != MarketDealRecords.PROPOSED:
		return answer(deal_id)
	MarketDealRecords.set_state(deal_id, MarketDealRecords.NEGOTIATING, date, "")
	return answer(deal_id)


static func agree(deal_id: String, date: String, mode: Dictionary = {}) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	var state := str(deal.get("state", ""))
	if not [MarketDealRecords.PROPOSED, MarketDealRecords.NEGOTIATING,
			MarketDealRecords.AGREED].has(state):
		return answer(deal_id)
	var window_id := str(MarketDealRules.window(deal, date).get("detail", ""))
	var fields := {"window_id": window_id}
	if window_id != "":
		deal["window_id"] = window_id
		MarketDealRecords.update(deal_id, fields)
	var verdict := MarketDealRules.validate(deal, date, mode)
	if not bool(verdict.get("ok", false)):
		var code := str(verdict.get("code", MarketDealRules.TERMS))
		MarketDealRecords.set_state(deal_id, MarketDealRecords.FAILED, date, code)
		var failed := answer(deal_id)
		failed["detail"] = str(verdict.get("detail", ""))
		return failed
	if needs_clearance(deal):
		fields["clears_on"] = FixtureCalendar.add_days(date, clearance_days(deal_id))
		MarketDealRecords.update(deal_id, fields)
		MarketDealRecords.set_state(deal_id, MarketDealRecords.CLEARANCE_PENDING, date, "")
		_write_pending_registration(deal)
		var pending := answer(deal_id)
		pending["clears_on"] = str(fields["clears_on"])
		return pending
	MarketDealRecords.set_state(deal_id, MarketDealRecords.AGREED, date, "")
	var agreed := answer(deal_id)
	agreed["ok"] = true
	return agreed


static func seal(deal_id: String, date: String, mode: Dictionary = {}) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	var state := str(deal.get("state", ""))
	if state == MarketDealRecords.SIGNED:
		var done := answer(deal_id)
		done["duplicate"] = true
		return done
	if state == MarketDealRecords.CLEARANCE_PENDING:
		return answer(deal_id)
	if state != MarketDealRecords.AGREED:
		return answer(deal_id)
	var verdict := MarketDealRules.validate(deal, date, mode)
	if not bool(verdict.get("ok", false)):
		var code := str(verdict.get("code", MarketDealRules.TERMS))
		MarketDealRecords.set_state(deal_id, MarketDealRecords.FAILED, date, code)
		return answer(deal_id)
	return commit(deal, date, mode)


static func resolve_clearance(deal_id: String, date: String, mode: Dictionary = {}) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	if str(deal.get("state", "")) != MarketDealRecords.CLEARANCE_PENDING:
		return answer(deal_id)
	var forced := str(mode.get("clearance", ""))
	var passed := forced == "pass"
	if forced == "":
		if date < str(deal.get("clears_on", "")):
			var waiting := answer(deal_id)
			waiting["ok"] = false
			return waiting
		if not _window_open_for(deal, date):
			MarketDealRecords.set_state(deal_id, MarketDealRecords.FAILED, date,
				MarketDealRules.WINDOW_CLOSED)
			_close_pending_registration(deal)
			return answer(deal_id)
		passed = MarketSeed.unit(_seed(), deal_id, 5) \
			>= MarketRules.number("deal", "clearance_fail_share", 0.08)
	if not passed:
		MarketDealRecords.set_state(deal_id, MarketDealRecords.FAILED, date,
			MarketDealRules.CLEARANCE)
		_close_pending_registration(deal)
		return answer(deal_id)
	MarketDealRecords.update(deal_id, {"clears_on": ""})
	MarketDealRecords.set_state(deal_id, MarketDealRecords.AGREED, date, "cleared")
	if bool(mode.get("defer", false)):
		var cleared := answer(deal_id)
		cleared["ok"] = true
		return cleared
	return seal(deal_id, date, {})


static func block(deal_id: String, date: String, note: String = "") -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	if str(deal.get("state", "")) == MarketDealRecords.SIGNED:
		return answer(deal_id)
	MarketDealRecords.update(deal_id, {"god": "block"})
	MarketDealRecords.set_state(deal_id, MarketDealRecords.BLOCKED, date, MarketDealRules.BLOCKED)
	var out := answer(deal_id)
	out["note"] = note
	return out


static func force(deal_id: String, date: String) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	MarketDealRecords.update(deal_id, {"god": "force"})
	var agreed := agree(deal_id, date, {"force": true})
	if not bool(agreed.get("ok", false)):
		return agreed
	return seal(deal_id, date, {"force": true})


static func rewrite(deal_id: String, terms: Dictionary, date: String) -> Dictionary:
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"ok": false, "reason": "no_deal"}
	if str(deal.get("state", "")) == MarketDealRecords.SIGNED:
		return answer(deal_id)
	var fields := {"state": MarketDealRecords.PROPOSED, "reason": "", "god": "rewrite",
		"deal_terms": JSON.stringify(terms)}
	for key in ["fee", "wage", "signing_bonus", "agent_fee", "years"]:
		if terms.has(key):
			fields[key] = int(terms[key])
	MarketDealRecords.update(deal_id, fields)
	MarketDealRecords.event(deal_id, date, MarketDealRecords.PROPOSED, "rewrite")
	return agree(deal_id, date, {})


static func answer(deal_id: String) -> Dictionary:
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


static func needs_clearance(deal: Dictionary) -> bool:
	var from_club := MarketDealRules.club_row(str(deal.get("from_club_id", "")))
	var to_club := MarketDealRules.club_row(str(deal.get("to_club_id", "")))
	if from_club.is_empty() or to_club.is_empty():
		return false
	return MarketWindows.country_of_club(from_club) != MarketWindows.country_of_club(to_club)


static func clearance_days(deal_id: String) -> int:
	var low := MarketRules.count("deal", "clearance_days_min", 1)
	var high := maxi(MarketRules.count("deal", "clearance_days_max", 5), low)
	var span := high - low + 1
	return low + MarketSeed.mix(_seed(), deal_id, 7) % span


static func commit(deal: Dictionary, date: String, mode: Dictionary = {}) -> Dictionary:
	return MarketDealCommit.run(deal, date, mode)


static func _write_pending_registration(deal: Dictionary) -> void:
	var player_id := str(deal.get("player_id", ""))
	var buyer := str(deal.get("to_club_id", ""))
	var club := MarketDealRules.club_row(buyer)
	var competition_id := str(club.get("competition_id", ""))
	if player_id == "" or competition_id == "":
		return
	var age := int(PLDatabase.row("SELECT age FROM player WHERE id = ?;", [player_id]).get(
		"age", 0))
	var exempt := 1 if MarketLists.player_exempt(player_id) or (age > 0 and age < 21) else 0
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index, u21_exempt) "
		+ "VALUES (?, ?, ?, ?, 'pending', 'clearance', ?, ?, ?);",
		[player_id, competition_id, buyer, str(deal.get("kind", PERMANENT)),
			str(deal.get("id", "")), int(deal.get("season_index", 0)), exempt])


static func _close_pending_registration(deal: Dictionary) -> void:
	var player_id := str(deal.get("player_id", ""))
	var buyer := str(deal.get("to_club_id", ""))
	if player_id == "" or buyer == "":
		return
	PLDatabase.execute(
		"DELETE FROM player_registration WHERE club_id = ? AND state = 'pending' "
		+ "AND player_id = ?;", [buyer, player_id])


static func _window_open_for(deal: Dictionary, date: String) -> bool:
	var buyer := MarketDealRules.club_row(str(deal.get("to_club_id", "")))
	if buyer.is_empty():
		return false
	var kind: String = MarketWindows.FREE_AGENT if MarketDealRules.is_free_agent(deal) \
		else MarketWindows.FEE
	var seller := MarketDealRules.club_row(str(deal.get("from_club_id", "")))
	return bool(MarketWindows.allows(kind, date, MarketWindows.country_of_club(buyer),
		MarketWindows.country_of_club(seller)).get("ok", false))


static func _seed() -> int:
	if LeagueSave.current == null:
		return 0
	return int(str(LeagueSave.current.meta.get("seed", "0")))
