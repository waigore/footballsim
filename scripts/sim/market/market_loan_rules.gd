class_name MarketLoanRules
extends RefCounted


const OK := "ok"
const CAP_IN := "loan_cap_in"
const CAP_OUT := "loan_cap_out"
const CAP_PAIR := "loan_cap_pair"
const SPLIT := "loan_wage_split"
const TERMS := "loan_terms"
const BUY_TERMS := "loan_buy_terms"

const OPTION_KINDS := ["none", "option", "obligation"]
const TRIGGER_KINDS := ["", "appearances_n", "club_promoted", "league_position", "season_end"]


static func validate(season: LeagueSeason, parent_id: String, loanee_id: String, player_id: String,
		terms: Dictionary, date: String, exclude: String = "") -> Dictionary:
	if parent_id == "" or loanee_id == "" or player_id == "" or parent_id == loanee_id:
		return fail(TERMS, "no move")
	var index := _season_index(season)
	var window := MarketWindows.allows(
		MarketWindows.FEE, date, MarketWindows.country_of_club(_club(loanee_id)),
		MarketWindows.country_of_club(_club(parent_id)))
	if not bool(window.get("ok", false)):
		return fail("window_closed", str(window.get("reason", "window_closed")))
	if int(MarketLoanRecords.count_in(loanee_id, index, exclude)) >= cap("cap_in", 6):
		return fail(CAP_IN, "the loanee already holds the loan-in cap")
	if int(MarketLoanRecords.count_out(parent_id, index, exclude)) >= cap("cap_out", 6):
		return fail(CAP_OUT, "the parent already lends out the cap")
	if int(MarketLoanRecords.count_pair(parent_id, loanee_id, index, exclude)) >= cap("cap_pair", 2):
		return fail(CAP_PAIR, "the pair already holds the cap between them")
	var player := PLDatabase.row("SELECT id, club_id FROM player WHERE id = ?;", [player_id])
	if player.is_empty() or str(player.get("club_id", "x")) != parent_id:
		return fail("not_at_club", "the player is not at the parent club")
	if not MarketDealRecords.live_for(player_id).is_empty():
		return fail("live_deal", "another deal is live")
	var terms_check := _terms(terms, date)
	if not bool(terms_check.get("ok", false)):
		return terms_check
	var split := split_of(int(terms_check.get("wage", 0)), terms)
	if int(split["parent"]) + int(split["loanee"]) != int(terms_check.get("wage", 0)):
		return fail(SPLIT, "the two shares do not sum to the wage")
	return {"ok": true, "code": OK, "detail": "", "split": split,
		"wage": terms_check.get("wage", 0), "window_id": str(window.get("window_id", "")),
		"start_date": str(terms_check.get("start_date", date)),
		"end_date": str(terms_check.get("end_date", ""))}


static func split_of(wage: int, terms: Dictionary) -> Dictionary:
	var loanee := clampi(int(terms.get("wage_loanee", wage)), 0, wage)
	return {"parent": wage - loanee, "loanee": loanee}


static func cap(key: String, fallback: int) -> int:
	return maxi(MarketRules.count("loan", key, fallback), 0)


static func _terms(terms: Dictionary, date: String) -> Dictionary:
	var kind := str(terms.get("option_kind", "none"))
	if not OPTION_KINDS.has(kind):
		return fail(BUY_TERMS, "the buy term is unknown")
	var trigger := str(terms.get("trigger_kind", ""))
	if not TRIGGER_KINDS.has(trigger):
		return fail(BUY_TERMS, "the trigger is unknown")
	if kind == "obligation" and int(terms.get("buy_fee", 0)) <= 0:
		return fail(BUY_TERMS, "an obligation needs a fee")
	if kind != "none" and int(terms.get("buy_fee", 0)) < 0:
		return fail(BUY_TERMS, "the buy fee is negative")
	var wage := int(terms.get("wage", 0))
	if wage < MarketRules.count("deal", "wage_min", 1):
		return fail(TERMS, "the wage is missing")
	var start := str(terms.get("start_date", date))
	var end := str(terms.get("end_date", ""))
	if end == "":
		end = FixtureCalendar.add_days(start, maxi(int(terms.get("days", 180)), 1))
	if end <= start:
		return fail(TERMS, "the loan ends before it starts")
	var span := FixtureCalendar.days_from(end) - FixtureCalendar.days_from(start)
	if span < MarketRules.count("loan", "days_min", 28) \
			or span > MarketRules.count("loan", "days_max", 330):
		return fail(TERMS, "the loan term is off its band")
	return {"ok": true, "wage": wage, "start_date": start, "end_date": end}


static func _season_index(season: LeagueSeason) -> int:
	if season != null and season.save != null:
		return season.save.season_index()
	return 0


static func _club(club_id: String) -> Dictionary:
	if club_id == "":
		return {}
	return PLDatabase.row("SELECT id, competition_id, country, stub FROM club WHERE id = ?;",
		[club_id])


static func fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
