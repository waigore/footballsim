class_name MarketDealRules
extends RefCounted


const OK := "ok"
const WINDOW_CLOSED := "window_closed"
const NOT_AT_CLUB := "not_at_club"
const LIVE_DEAL := "live_deal"
const TERMS := "terms_incomplete"
const CONSENT := "refused_consent"
const NO_CASH := "no_cash"
const FFP := "ffp"
const LIST := "list_refused"
const CLEARANCE := "no_clearance"
const BLOCKED := "god_blocked"
const ORDER := ["window", "club", "terms", "consent", "cash", "ffp", "list"]


static func validate(deal: Dictionary, date: String, mode: Dictionary = {}) -> Dictionary:
	if deal.is_empty():
		return fail(TERMS, "no deal")
	if MarketDealRecords.vetoed(str(deal.get("player_id", "")), str(deal.get("to_club_id", "")),
			str(deal.get("window_id", ""))):
		return fail(BLOCKED, "god blocked this buyer this window")
	for name in ORDER:
		var verdict := check(str(name), deal, date, mode)
		if not bool(verdict.get("ok", false)):
			return verdict
	return pass_with("")


static func check(name: String, deal: Dictionary, date: String, mode: Dictionary = {}) -> Dictionary:
	match name:
		"window":
			return window(deal, date)
		"club":
			return club(deal)
		"terms":
			return terms(deal)
		"consent":
			return consent(deal, mode)
		"cash":
			return cash(deal, mode)
		"ffp":
			return ffp(deal, mode)
		"list":
			return list_check(deal, mode)
	return pass_with("")


static func window(deal: Dictionary, date: String) -> Dictionary:
	var free_agent := is_free_agent(deal)
	var buyer := club_row(str(deal.get("to_club_id", "")))
	if buyer.is_empty():
		return fail(TERMS, "no buying club")
	var seller := club_row(str(deal.get("from_club_id", "")))
	var kind: String = MarketWindows.FREE_AGENT if free_agent else MarketWindows.FEE
	var verdict := MarketWindows.allows(kind, date, MarketWindows.country_of_club(buyer),
		MarketWindows.country_of_club(seller))
	if not bool(verdict.get("ok", false)):
		return fail(WINDOW_CLOSED, str(verdict.get("reason", "window_closed")))
	return pass_with(str(verdict.get("window_id", "")))


static func club(deal: Dictionary) -> Dictionary:
	var player := PLDatabase.row("SELECT id, club_id FROM player WHERE id = ?;",
		[str(deal.get("player_id", ""))])
	if player.is_empty():
		return fail(NOT_AT_CLUB, "no such player")
	if str(player.get("club_id", "x")) != str(deal.get("from_club_id", "")):
		return fail(NOT_AT_CLUB, "the player is not at the selling club")
	var live := MarketDealRecords.live_for(str(deal.get("player_id", "")),
		str(deal.get("id", "")))
	if not live.is_empty():
		return fail(LIVE_DEAL, str(live.get("id", "")))
	return pass_with("")


static func terms(deal: Dictionary) -> Dictionary:
	var to_club := str(deal.get("to_club_id", ""))
	if to_club == "" or to_club == str(deal.get("from_club_id", "")):
		return fail(TERMS, "no move")
	var fee := int(deal.get("fee", 0))
	var wage := int(deal.get("wage", 0))
	var years := int(deal.get("years", 0))
	if fee < MarketRules.count("deal", "fee_min", 0):
		return fail(TERMS, "the fee is below the floor")
	if wage < MarketRules.count("deal", "wage_min", 1):
		return fail(TERMS, "the wage is missing")
	if years < MarketRules.count("deal", "years_min", 1) \
			or years > MarketRules.count("deal", "years_max", 5):
		return fail(TERMS, "the term is off its band")
	return pass_with("")


static func consent(deal: Dictionary, mode: Dictionary = {}) -> Dictionary:
	if bool(mode.get("force", false)):
		return pass_with("forced")
	var current := int(MarketDealRecords.active_contract(str(deal.get("player_id", ""))).get(
		"wage", 0))
	if current > 0 and int(deal.get("wage", 0)) < current:
		return fail(CONSENT, "the wage is below his contract")
	return pass_with("")


static func cash(deal: Dictionary, mode: Dictionary = {}) -> Dictionary:
	if bool(mode.get("force", false)):
		return pass_with("forced")
	var buyer := str(deal.get("to_club_id", ""))
	var needed := int(deal.get("fee", 0)) + int(deal.get("agent_fee", 0)) \
		+ int(deal.get("signing_bonus", 0))
	if not MarketFinance.can_afford(buyer, needed):
		return fail(NO_CASH, "the buying club cannot afford the deal")
	return pass_with("")


static func ffp(deal: Dictionary, mode: Dictionary = {}) -> Dictionary:
	if bool(mode.get("force", false)):
		return pass_with("ffp_override")
	var buyer := str(deal.get("to_club_id", ""))
	var cost := MarketFinance.amortisation(int(deal.get("fee", 0)), int(deal.get("years", 1))) \
		+ int(deal.get("wage", 0)) * 52 + int(deal.get("agent_fee", 0))
	if MarketFinance.ffp_headroom(buyer) - cost < 0:
		return fail(FFP, "the deal breaches the club's headroom")
	return pass_with("")


static func list_check(deal: Dictionary, mode: Dictionary = {}) -> Dictionary:
	if str(mode.get("list", "")) == "refuse":
		return fail(LIST, "the squad list refuses the registration")
	return pass_with("")


static func is_free_agent(deal: Dictionary) -> bool:
	if str(deal.get("from_club_id", "")) == "":
		return true
	if int(deal.get("fee", 0)) > 0:
		return false
	return MarketDealRecords.active_contract(str(deal.get("player_id", ""))).is_empty()


static func club_row(club_id: String) -> Dictionary:
	if club_id == "":
		return {}
	return PLDatabase.row("SELECT id, competition_id, country, stub FROM club WHERE id = ?;",
		[club_id])


static func pass_with(note: String) -> Dictionary:
	return {"ok": true, "code": OK, "detail": note}


static func fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
