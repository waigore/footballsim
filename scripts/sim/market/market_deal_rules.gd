class_name MarketDealRules
extends RefCounted


const ORDER := ["window", "player", "terms", "consent", "cash", "ffp", "registration",
	"clearance"]


static func run(deal: Dictionary, options: Dictionary = {}) -> Dictionary:
	var results: Array = []
	var registration_state := MarketDealRecords.REGISTERED
	for name in ORDER:
		var check := _check(str(name), deal, options)
		results.append({"name": str(name), "ok": bool(check.get("ok", false)),
			"reason": str(check.get("reason", ""))})
		if bool(check.get("ok", false)):
			continue
		if str(name) == "registration":
			registration_state = MarketDealRecords.INELIGIBLE
			continue
		return {"ok": false, "reason": str(check.get("reason", "")), "results": results,
			"registration_state": registration_state}
	return {"ok": true, "reason": "", "results": results,
		"registration_state": registration_state}


static func window(deal: Dictionary, options: Dictionary) -> Dictionary:
	if str(options.get("inject", "")) == "window_closed":
		return _result(false, MarketDealRecords.WINDOW_CLOSED)
	var date := _date(deal, options)
	var buyer := _country(str(deal.get("to_club_id", "")))
	var seller := _country(str(deal.get("from_club_id", "")))
	var kind: String = MarketWindows.FREE_AGENT if str(deal.get("from_club_id", "")) == "" \
		else MarketWindows.FEE
	var allow := MarketWindows.allows(kind, date, buyer, seller)
	if not bool(allow.get("ok", false)):
		return _result(false, str(allow.get("reason", MarketDealRecords.WINDOW_CLOSED)))
	return _result(true, MarketDealRecords.OPEN if str(allow.get("reason", "")) == "open" \
		else str(allow.get("reason", MarketDealRecords.OPEN)))


static func player(deal: Dictionary, options: Dictionary) -> Dictionary:
	var inject := str(options.get("inject", ""))
	if inject == "not_at_club":
		return _result(false, MarketDealRecords.NOT_AT_CLUB)
	if inject == "live_deal":
		return _result(false, MarketDealRecords.LIVE_DEAL)
	var player_id := str(deal.get("player_id", ""))
	var row := PLDatabase.row("SELECT id, club_id FROM player WHERE id = ?;", [player_id])
	if row.is_empty():
		return _result(false, MarketDealRecords.NOT_AT_CLUB)
	var from_club := str(deal.get("from_club_id", ""))
	if from_club == "":
		if str(row.get("club_id", "")) != "":
			return _result(false, MarketDealRecords.NOT_AT_CLUB)
	elif str(row.get("club_id", "")) != from_club:
		return _result(false, MarketDealRecords.NOT_AT_CLUB)
	var live := MarketDealRecords.live_for(player_id, str(deal.get("id", "")))
	if not live.is_empty():
		return _result(false, MarketDealRecords.LIVE_DEAL)
	var veto := MarketDealRecords.veto(player_id, str(deal.get("to_club_id", "")),
		str(deal.get("window_id", "")))
	if not veto.is_empty():
		return _result(false, MarketDealRecords.GOD_BLOCKED)
	return _result(true, "")


static func terms(deal: Dictionary, options: Dictionary) -> Dictionary:
	if str(options.get("inject", "")) == "terms":
		return _result(false, MarketDealRecords.TERMS_INCOMPLETE)
	var to_club := str(deal.get("to_club_id", ""))
	var from_club := str(deal.get("from_club_id", ""))
	var fee := int(deal.get("fee", 0))
	var wage := int(deal.get("wage", 0))
	var years := int(deal.get("years", 0))
	var complete := str(deal.get("player_id", "")) != "" and to_club != "" \
		and to_club != from_club and MarketDealRecords.KINDS.has(str(deal.get("kind", ""))) \
		and fee >= 0 and wage > 0 and years >= 1 and years <= 6
	if from_club == "" and fee > 0:
		complete = false
	return _result(complete, MarketDealRecords.TERMS_INCOMPLETE)


static func consent(deal: Dictionary, options: Dictionary) -> Dictionary:
	if bool(options.get("force", false)):
		return _result(true, "")
	if str(options.get("inject", "")) == "consent":
		return _result(false, MarketDealRecords.REFUSED_CONSENT)
	if int(deal.get("consent", 0)) != 1:
		return _result(false, MarketDealRecords.REFUSED_CONSENT)
	return _result(true, "")


static func cash(deal: Dictionary, options: Dictionary) -> Dictionary:
	if bool(options.get("force", false)):
		return _result(true, "")
	if str(options.get("inject", "")) == "cash":
		return _result(false, MarketDealRecords.NO_CASH)
	var fee := int(deal.get("fee", 0))
	if MarketFinance.cash(str(deal.get("to_club_id", ""))) < fee:
		return _result(false, MarketDealRecords.NO_CASH)
	return _result(true, "")


static func ffp(_deal: Dictionary, options: Dictionary) -> Dictionary:
	if bool(options.get("force", false)):
		return _result(true, "")
	if str(options.get("inject", "")) == "ffp":
		return _result(false, MarketDealRecords.FFP)
	return _result(true, "")


static func registration(_deal: Dictionary, options: Dictionary) -> Dictionary:
	var inject := str(options.get("inject", ""))
	if inject in ["registration", "list_full", "homegrown_min", "permit"]:
		return _result(false, MarketDealRecords.LIST_REFUSED)
	return _result(true, "")


static func clearance(_deal: Dictionary, options: Dictionary) -> Dictionary:
	if str(options.get("inject", "")) == "clearance":
		return _result(false, MarketDealRecords.NO_CLEARANCE)
	return _result(true, "")


static func _check(name: String, deal: Dictionary, options: Dictionary) -> Dictionary:
	match name:
		"window":
			return window(deal, options)
		"player":
			return player(deal, options)
		"terms":
			return terms(deal, options)
		"consent":
			return consent(deal, options)
		"cash":
			return cash(deal, options)
		"ffp":
			return ffp(deal, options)
		"registration":
			return registration(deal, options)
		"clearance":
			return clearance(deal, options)
	return _result(false, MarketDealRecords.TERMS_INCOMPLETE)


static func _date(deal: Dictionary, options: Dictionary) -> String:
	var date := str(options.get("date", ""))
	var fallback: String = date if date != "" else str(deal.get("created_on", ""))
	return fallback


static func _country(club_id: String) -> String:
	if club_id == "":
		return ""
	return MarketWindows.country_of_club(PLDatabase.row("SELECT * FROM club WHERE id = ?;",
		[club_id]))


static func _result(ok: bool, reason: String) -> Dictionary:
	return {"ok": ok, "reason": reason}
