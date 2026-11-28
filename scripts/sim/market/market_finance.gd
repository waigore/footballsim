class_name MarketFinance
extends RefCounted


const KIND_GATE := "gate"
const KIND_COMMERCIAL := "commercial"
const KIND_PRIZE := "prize"
const KIND_FEE := "fee"
const KIND_WAGE := "wage"
const KIND_AGENT := "agent"
const KIND_SELL_ON := "sell_on"
const KIND_SOLIDARITY := "solidarity"
const KIND_TRAINING := "training"
const KIND_FFP := "ffp"
const KIND_AMORTISATION := "amortisation"

const KINDS := [KIND_GATE, KIND_COMMERCIAL, KIND_PRIZE, KIND_FEE, KIND_WAGE, KIND_AGENT,
	KIND_SELL_ON, KIND_SOLIDARITY, KIND_TRAINING, KIND_FFP, KIND_AMORTISATION]

const CASH_KINDS := [KIND_GATE, KIND_COMMERCIAL, KIND_PRIZE, KIND_FEE, KIND_WAGE, KIND_AGENT,
	KIND_SELL_ON, KIND_SOLIDARITY, KIND_TRAINING, KIND_FFP]

static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path and path != "":
		return _ready
	_ready_path = path
	_ready = path != "" and not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'club_finance';").is_empty()
	return _ready


static func bootstrap(save: LeagueSave) -> Dictionary:
	if save == null or not save.ensure_open() or not available():
		return {"ok": false, "reason": "no_save", "clubs": 0}
	if int(PLDatabase.row("SELECT COUNT(*) AS n FROM club_finance;").get("n", 0)) > 0:
		return {"ok": true, "skipped": true, "clubs": 0}
	var date := save.current_date()
	var written := 0
	var values: Array = []
	var bindings: Array = []
	for club in PLDatabase.rows("SELECT * FROM club ORDER BY id;"):
		var cid := str(club.get("competition_id", ""))
		if not save.actives.has(cid):
			continue
		var revenue := MarketWages.revenue_anchor(club)
		var clubs := int(save.rules_for(cid).get("clubs", 20))
		values.append("(?, ?, ?, ?, ?, ?, ?)")
		bindings.append_array([str(club["id"]), MarketPurse.opening(revenue, cid, clubs),
			MarketPurse.reputation(revenue, 0, clubs), revenue, MarketWages.wage_budget(club), date,
			save.season_index()])
		written += 1
	if not values.is_empty():
		PLDatabase.execute("INSERT INTO club_finance (club_id, cash, reputation, revenue_base, "
			+ "wage_budget, updated_on, season_index) VALUES " + ", ".join(values) + ";",
			bindings)
	return {"ok": true, "skipped": false, "clubs": written}


static func club(club_id: String) -> Dictionary:
	if club_id == "" or not available():
		return {}
	return PLDatabase.row("SELECT * FROM club_finance WHERE club_id = ?;", [club_id])


static func cash(club_id: String) -> int:
	return int(club(club_id).get("cash", 0))


static func revenue_base(club_id: String) -> int:
	return int(club(club_id).get("revenue_base", 0))


static func wage_budget(club_id: String) -> int:
	return int(club(club_id).get("wage_budget", 0))


static func reputation(club_id: String) -> int:
	return int(club(club_id).get("reputation", 0))


static func annual_wages(club_id: String) -> int:
	if club_id == "" or not available():
		return 0
	var row := PLDatabase.row(
		"SELECT COALESCE(SUM(wage), 0) AS total FROM player_contract "
		+ "WHERE club_id = ? AND status = 'active';", [club_id])
	return int(row.get("total", 0)) * 52


static func amortisation_season(club_id: String, season_index: int = -1) -> int:
	if club_id == "" or not available():
		return 0
	var season: int = season_index
	if season < 0:
		season = LeagueSave.current.season_index() if LeagueSave.current != null else 0
	var row := PLDatabase.row(
		"SELECT COALESCE(SUM(amount), 0) AS total FROM club_ledger "
		+ "WHERE club_id = ? AND kind = ? AND season_index = ?;",
		[club_id, KIND_AMORTISATION, season])
	return int(row.get("total", 0))


static func ffp_headroom(club_id: String) -> int:
	return MarketFFP.headroom(club_id)


static func ledger_tail(club_id: String, limit: int = 8) -> Array:
	if club_id == "" or not available():
		return []
	return PLDatabase.rows(
		"SELECT * FROM club_ledger WHERE club_id = ? ORDER BY id DESC LIMIT ?;",
		[club_id, limit])


static func post(club_id: String, date: String, kind: String, amount: int,
		counterparty: String = "", player_id: String = "", deal_id: String = "") -> bool:
	if club_id == "" or not KINDS.has(kind) or not available():
		return false
	var season := LeagueSave.current.season_index() if LeagueSave.current != null else 0
	if not PLDatabase.execute(
			"INSERT INTO club_ledger (season_index, date, club_id, kind, amount, counterparty, "
			+ "player_id, deal_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
			[season, date, club_id, kind, amount, counterparty, player_id, deal_id]):
		return false
	if not CASH_KINDS.has(kind):
		return true
	return PLDatabase.execute(
		"UPDATE club_finance SET cash = cash + ?, updated_on = ? WHERE club_id = ?;",
		[amount, date, club_id])


static func can_afford(club_id: String, amount: int) -> bool:
	return cash(club_id) >= amount


static func invalidate() -> void:
	_ready_path = ""
	MarketFinanceFlows.invalidate()



static func amortisation(fee: int, years: int = 0) -> int:
	var span: int = years
	if span <= 0:
		span = int(MarketRules.section("finance").get("amortisation_years", 4))
	if fee <= 0 or span <= 0:
		return 0
	return int(round(float(fee) / float(span)))


static func post_amortisation(club_id: String, date: String, fee: int, years: int = 0,
		player_id: String = "") -> int:
	var amount := amortisation(fee, years)
	if amount <= 0:
		return 0
	post(club_id, date, KIND_AMORTISATION, amount, "amortisation", player_id)
	return amount
