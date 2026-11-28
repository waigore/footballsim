class_name MarketFinance
extends RefCounted


const KIND_GATE := "gate"
const KIND_COMMERCIAL := "commercial"
const KIND_PRIZE := "prize"
const KIND_FEE := "fee"
const KIND_WAGE := "wage"
const KIND_AGENT := "agent"
const KIND_SOLIDARITY := "solidarity"
const KIND_TRAINING := "training"
const KIND_FFP := "ffp"
const KIND_AMORTISATION := "amortisation"

const KINDS := [KIND_GATE, KIND_COMMERCIAL, KIND_PRIZE, KIND_FEE, KIND_WAGE, KIND_AGENT,
	KIND_SOLIDARITY, KIND_TRAINING, KIND_FFP, KIND_AMORTISATION]

const CASH_KINDS := [KIND_GATE, KIND_COMMERCIAL, KIND_PRIZE, KIND_FEE, KIND_WAGE, KIND_AGENT,
	KIND_SOLIDARITY, KIND_TRAINING, KIND_FFP]

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
	return revenue_base(club_id) - annual_wages(club_id) - amortisation_season(club_id)


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


static func gate(club_id: String, form: float = 0.0) -> int:
	var row := PLDatabase.row(
		"SELECT capacity, competition_id FROM club WHERE id = ?;", [club_id])
	if row.is_empty():
		return 0
	var spec := MarketRules.section("finance")
	var factor := clampf(float(spec.get("attendance", 0.92))
		+ float(spec.get("form_swing", 0.06)) * clampf(form, -1.0, 1.0), 0.0, 1.0)
	var cid := str(row.get("competition_id", ""))
	var price := float(MarketRules.ticket_price(cid)) * MarketRules.revenue_multiplier(cid)
	return int(round(float(row.get("capacity", 0)) * factor * price))


static func tick_gates(season: LeagueSeason, date: String) -> int:
	if season == null or season.save == null or not available() or date == "":
		return 0
	var upto := str(season.save.meta.get("gates_through", ""))
	var comps: Array = season.save.actives
	if comps.is_empty():
		return 0
	var marks := PackedStringArray()
	var bindings: Array = [upto, date]
	for cid in comps:
		marks.append("?")
		bindings.append(str(cid))
	var spec := MarketRules.section("finance")
	var attendance := float(spec.get("attendance", 0.92))
	var swing := float(spec.get("form_swing", 0.06))
	var values: Array = []
	var rows: Array = []
	var totals := {}
	for row in PLDatabase.rows(
			"SELECT f.home_club_id AS club_id, f.kickoff AS kickoff, c.capacity AS capacity, "
			+ "c.competition_id AS cid, t.points AS points, t.played AS played "
			+ "FROM league_fixture f JOIN club c ON c.id = f.home_club_id "
			+ "LEFT JOIN league_table t ON t.club_id = f.home_club_id "
			+ "AND t.competition_id = f.competition_id "
			+ "WHERE f.status = 'played' AND f.kickoff > ? AND f.kickoff <= ? "
			+ "AND f.competition_id IN (" + ",".join(marks) + ") "
			+ "ORDER BY f.kickoff, f.home_club_id;", bindings):
		var played := int(row.get("played", 0) or 0)
		var form := 0.0
		if played > 0:
			form = clampf((float(row.get("points", 0)) / float(played) / 3.0) * 2.0 - 1.0,
				-1.0, 1.0)
		var cid := str(row.get("cid", ""))
		var factor := clampf(attendance + swing * form, 0.0, 1.0)
		var amount := int(round(float(row.get("capacity", 0)) * factor
			* float(MarketRules.ticket_price(cid)) * MarketRules.revenue_multiplier(cid)))
		if amount <= 0:
			continue
		var club_id := str(row["club_id"])
		values.append("(?, ?, ?, 'gate', ?, 'gate', '', '')")
		rows.append_array([season.save.season_index(), str(row["kickoff"]), club_id, amount])
		totals[club_id] = int(totals.get(club_id, 0)) + amount
	if values.is_empty():
		season.save.put_meta("gates_through", date)
		return 0
	var cases := PackedStringArray()
	var ids: Array = []
	var binds: Array = []
	for club_id in totals.keys():
		cases.append("WHEN ? THEN ?")
		binds.append_array([str(club_id), int(totals[club_id])])
		ids.append(str(club_id))
	binds.append(date)
	binds.append_array(ids)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("INSERT INTO club_ledger (season_index, date, club_id, kind, amount, "
		+ "counterparty, player_id, deal_id) VALUES " + ", ".join(values) + ";", rows)
	PLDatabase.execute("UPDATE club_finance SET cash = cash + CASE club_id "
		+ " ".join(cases) + " ELSE 0 END, updated_on = ? WHERE club_id IN ("
		+ ",".join(MarketPurse.marks(ids.size())) + ");", binds)
	PLDatabase.transaction("COMMIT;")
	season.save.put_meta("gates_through", date)
	return values.size()


static func form_factor(club_id: String) -> float:
	var row := PLDatabase.row(
		"SELECT played, points FROM league_table WHERE club_id = ? LIMIT 1;", [club_id])
	var played := int(row.get("played", 0))
	if played <= 0:
		return 0.0
	return clampf((float(row.get("points", 0)) / float(played) / 3.0) * 2.0 - 1.0, -1.0, 1.0)


static func month(date: String) -> int:
	if not available():
		return 0
	var bills := {}
	for row in PLDatabase.rows(
			"SELECT club_id, SUM(wage) AS w FROM player_contract WHERE status = 'active' "
			+ "GROUP BY club_id;"):
		bills[str(row["club_id"])] = int(row.get("w", 0)) * 52
	var share := float(MarketRules.section("finance").get("commercial_share", 0.4))
	var posted := 0
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for row in PLDatabase.rows("SELECT club_id, revenue_base FROM club_finance ORDER BY club_id;"):
		var club_id := str(row["club_id"])
		var commercial := int(round(float(row.get("revenue_base", 0)) * share / 12.0))
		if commercial > 0:
			post(club_id, date, KIND_COMMERCIAL, commercial, "commercial")
			posted += 1
		var wages := int(round(float(int(bills.get(club_id, 0))) / 12.0))
		if wages > 0:
			post(club_id, date, KIND_WAGE, -wages, "squad")
	PLDatabase.transaction("COMMIT;")
	return posted


static func season_end(season: LeagueSeason, played_index: int) -> int:
	if season == null or season.save == null or not available():
		return 0
	var date := season.save.current_date()
	var posted := 0
	var tables := {}
	for row in PLDatabase.rows(
			"SELECT club_id, competition_id FROM league_table "
			+ "ORDER BY competition_id, points DESC, (gf - ga) DESC, gf DESC, club_id;"):
		var cid := str(row["competition_id"])
		if not tables.has(cid):
			tables[cid] = 0
		tables[cid] = int(tables[cid]) + 1
		var place := int(tables[cid])
		var prize := MarketPurse.prize(cid, place, MarketPurse.size(cid))
		if prize > 0:
			_post_season(str(row["club_id"]), date, KIND_PRIZE, prize, cid, played_index)
			posted += 1
		var tv := int(round(float(prize) * float(MarketRules.section("prize").get("tv_share", 0.5))))
		if tv > 0:
			_post_season(str(row["club_id"]), date, KIND_COMMERCIAL, tv, "tv:" + cid, played_index)
	return posted


static func roll(season: LeagueSeason, start: String) -> int:
	if season == null or season.save == null or not available():
		return 0
	var updated := 0
	for club in PLDatabase.rows("SELECT * FROM club ORDER BY id;"):
		var club_id := str(club["id"])
		var cid := str(club.get("competition_id", ""))
		if not season.save.actives.has(cid):
			continue
		var archived := PLDatabase.row(
			"SELECT position FROM season_archive WHERE season_index = ? AND club_id = ?;",
			[season.save.season_index() - 1, club_id])
		var clubs := int(season.save.rules_for(cid).get("clubs", 20))
		var revenue := MarketWages.revenue_anchor(club)
		updated += 1 if PLDatabase.execute(
			"UPDATE club_finance SET revenue_base = ?, wage_budget = ?, reputation = ?, "
			+ "updated_on = ?, season_index = ? WHERE club_id = ?;",
			[revenue, MarketWages.wage_budget(club),
			 MarketPurse.reputation(revenue, int(archived.get("position", 0)), clubs), start,
			 season.save.season_index(), club_id]) else 0
	return updated


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


static func _post_season(club_id: String, date: String, kind: String, amount: int,
		counterparty: String, season_index: int) -> void:
	if not PLDatabase.execute(
			"INSERT INTO club_ledger (season_index, date, club_id, kind, amount, counterparty) "
			+ "VALUES (?, ?, ?, ?, ?, ?);", [season_index, date, club_id, kind, amount,
				counterparty]):
		return
	PLDatabase.execute("UPDATE club_finance SET cash = cash + ? WHERE club_id = ?;",
		[amount, club_id])
