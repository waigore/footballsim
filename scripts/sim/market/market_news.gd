class_name MarketNews
extends RefCounted


const RUMOUR := "rumour"
const SIGNED := "signed"
const BLOCKED := "blocked"
const FAILED := "failed"
const FORCED := "forced"

const CAP := 500
const RUMOUR_FEE := 5_000_000
const RUMOUR_TOP := 6

static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path and path != "":
		return _ready
	_ready_path = path
	_ready = path != "" and not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'market_news';").is_empty()
	return _ready


static func on_state(deal_id: String, state: String, date: String) -> void:
	if not available() or deal_id == "":
		return
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return
	if state == MarketDealRecords.NEGOTIATING:
		if worthy(deal):
			create(RUMOUR, deal, date)
		return
	if state == MarketDealRecords.SIGNED:
		var kind := FORCED if str(deal.get("god", "")) == "force" else SIGNED
		create(kind, deal, date)
		return
	if state == MarketDealRecords.BLOCKED:
		create(BLOCKED, deal, date)
		return
	if state == MarketDealRecords.FAILED:
		create(FAILED, deal, date)


static func worthy(deal: Dictionary) -> bool:
	if int(deal.get("fee", 0)) >= RUMOUR_FEE:
		return true
	var top := top_six()
	return top.has(str(deal.get("from_club_id", ""))) or top.has(str(deal.get("to_club_id", "")))


static func top_six() -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT club_id FROM club_finance ORDER BY reputation DESC, club_id LIMIT ?;",
			[RUMOUR_TOP]):
		out.append(str(row["club_id"]))
	return out


static func create(kind: String, deal: Dictionary, date: String) -> bool:
	if not available() or kind == "":
		return false
	var deal_id := str(deal.get("id", ""))
	var key := "%s|%s" % [deal_id, kind]
	if not PLDatabase.row("SELECT id FROM market_news WHERE dedupe_key = ?;", [key]).is_empty():
		return false
	var season := int(deal.get("season_index", 0))
	var ok := PLDatabase.execute(
		"INSERT OR IGNORE INTO market_news (season_index, date, kind, deal_id, player_id, "
		+ "from_club_id, to_club_id, club_id, dedupe_key) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[season, date, kind, deal_id, str(deal.get("player_id", "")),
		 str(deal.get("from_club_id", "")), str(deal.get("to_club_id", "")),
		 str(deal.get("to_club_id", "")), key])
	if not ok:
		return false
	prune(season)
	return true


static func prune(season_index: int) -> int:
	if not available():
		return 0
	var extra := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM market_news WHERE season_index = ?;",
		[season_index]).get("n", 0)) - CAP
	if extra <= 0:
		return 0
	PLDatabase.execute(
		"DELETE FROM market_news WHERE season_index = ? AND id NOT IN "
		+ "(SELECT id FROM market_news WHERE season_index = ? ORDER BY id DESC LIMIT ?);",
		[season_index, season_index, CAP])
	return extra


static func count(season_index: int = -1) -> int:
	if not available():
		return 0
	if season_index < 0:
		return int(PLDatabase.row("SELECT COUNT(*) AS n FROM market_news;").get("n", 0))
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM market_news WHERE season_index = ?;",
		[season_index]).get("n", 0))


static func digest(date: String) -> Array:
	if date == "" or not available():
		return []
	return feed(-1, 12, date)


static func feed(season_index: int = -1, limit: int = 50, date: String = "") -> Array:
	if not available():
		return []
	var sql := ("SELECT * FROM market_news WHERE 1 = 1")
	var bindings: Array = []
	if season_index >= 0:
		sql += " AND season_index = ?"
		bindings.append(season_index)
	if date != "":
		sql += " AND date = ?"
		bindings.append(date)
	bindings.append(maxi(limit, 1))
	sql += " ORDER BY id DESC LIMIT ?;"
	var out: Array = []
	for row in PLDatabase.rows(sql, bindings):
		var item: Dictionary = row
		item["player_name"] = str(PLDatabase.row("SELECT name FROM player WHERE id = ?;",
			[str(row.get("player_id", ""))]).get("name", ""))
		item["from_name"] = _club_name(str(row.get("from_club_id", "")))
		item["to_name"] = _club_name(str(row.get("to_club_id", "")))
		item["headline"] = headline(item)
		out.append(item)
	return out


static func headline(item: Dictionary) -> String:
	var who := str(item.get("player_name", ""))
	if who == "":
		who = "A PLAYER"
	var to := str(item.get("to_name", ""))
	var from := str(item.get("from_name", ""))
	match str(item.get("kind", "")):
		RUMOUR:
			return "%s LINKED WITH %s" % [who.to_upper(), to.to_upper()]
		SIGNED:
			return "%s JOINS %s" % [who.to_upper(), to.to_upper()]
		FORCED:
			return "%s FORCED TO %s" % [who.to_upper(), to.to_upper()]
		BLOCKED:
			return "GOD BLOCKS %s TO %s" % [who.to_upper(), to.to_upper()]
		FAILED:
			return "%s MOVE FALLS THROUGH" % who.to_upper()
	return "%s %s %s" % [who.to_upper(), str(item.get("kind", "")).to_upper(), from.to_upper()]


static func _club_name(club_id: String) -> String:
	if club_id == "":
		return "FREE AGENT"
	return str(PLDatabase.row("SELECT name FROM club WHERE id = ?;", [club_id]).get(
		"name", club_id))


static func invalidate() -> void:
	_ready_path = ""
	_ready = false
