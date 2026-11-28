class_name MarketDealRecords
extends RefCounted


const PROPOSED := "proposed"
const NEGOTIATING := "negotiating"
const AGREED := "agreed"
const CLEARANCE_PENDING := "clearance_pending"
const SIGNED := "signed"
const WITHDRAWN := "withdrawn"
const FAILED := "failed"
const BLOCKED := "blocked"

const STATES := [PROPOSED, NEGOTIATING, AGREED, CLEARANCE_PENDING, SIGNED, WITHDRAWN,
	FAILED, BLOCKED]
const LIVE := [PROPOSED, NEGOTIATING, AGREED, CLEARANCE_PENDING]
const TERMINAL := [SIGNED, WITHDRAWN, FAILED, BLOCKED]

const KIND_PERMANENT := "permanent"
const KIND_LOAN := "loan"
const KINDS := [KIND_PERMANENT, KIND_LOAN]

const REGISTERED := "registered"
const PENDING := "pending"
const INELIGIBLE := "ineligible"
const CLOSED := "closed"
const REG_STATES := [REGISTERED, PENDING, INELIGIBLE, CLOSED]

const WINDOW_CLOSED := "window_closed"
const NOT_AT_CLUB := "not_at_club"
const LIVE_DEAL := "live_deal"
const TERMS_INCOMPLETE := "terms_incomplete"
const REFUSED_CONSENT := "refused_consent"
const NO_CASH := "no_cash"
const FFP := "ffp"
const LIST_REFUSED := "list_refused"
const NO_CLEARANCE := "no_clearance"
const GOD_BLOCKED := "god_blocked"
const OPEN := "open"

const REASONS := [WINDOW_CLOSED, NOT_AT_CLUB, LIVE_DEAL, TERMS_INCOMPLETE, REFUSED_CONSENT,
	NO_CASH, FFP, LIST_REFUSED, NO_CLEARANCE, GOD_BLOCKED, OPEN]

static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path and path != "":
		return _ready
	_ready_path = path
	_ready = path != "" and not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'deal';").is_empty()
	return _ready


static func insert(offer: Dictionary, date: String, season_index: int) -> String:
	if not available() or date == "":
		return ""
	var player_id := str(offer.get("player_id", ""))
	var id := next_id(player_id, date)
	var ok := PLDatabase.execute(
		"INSERT INTO deal (id, player_id, from_club_id, to_club_id, kind, state, reason, "
		+ "fee, wage, years, consent, window_id, clears_on, created_on, updated_on, "
		+ "signed_on, season_index, market_day) "
		+ "VALUES (?, ?, ?, ?, ?, ?, '', ?, ?, ?, ?, ?, '', ?, ?, '', ?, ?);",
		[id, player_id, str(offer.get("from_club_id", "")),
		str(offer.get("to_club_id", "")), _kind(offer), PROPOSED, int(offer.get("fee", 0)),
		int(offer.get("wage", 0)), maxi(int(offer.get("years", 1)), 1),
		int(offer.get("consent", 1)), str(offer.get("window_id", "")), date, date,
		season_index, date])
	if not ok:
		return ""
	add_event(id, PROPOSED, "", date, "")
	return id


static func next_id(player_id: String, date: String) -> String:
	var row := PLDatabase.row("SELECT COUNT(*) AS n FROM deal WHERE created_on = ?;", [date])
	return "deal:%s:%s:%d" % [player_id, date, int(row.get("n", 0)) + 1]


static func one(deal_id: String) -> Dictionary:
	if deal_id == "" or not available():
		return {}
	return PLDatabase.row("SELECT * FROM deal WHERE id = ?;", [deal_id])


static func latest_for_player(player_id: String) -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM deal WHERE player_id = ? ORDER BY created_on DESC, rowid DESC LIMIT 1;",
		[player_id])


static func live_for(player_id: String, exclude_id: String = "") -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM deal WHERE player_id = ? AND id <> ? "
		+ "AND state IN ('proposed', 'negotiating', 'agreed', 'clearance_pending') "
		+ "ORDER BY created_on DESC, rowid DESC LIMIT 1;", [player_id, exclude_id])


static func veto(player_id: String, buyer_id: String, window_id: String) -> Dictionary:
	if player_id == "" or buyer_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM deal WHERE player_id = ? AND to_club_id = ? AND state = 'blocked' "
		+ "AND reason = 'god_blocked' AND window_id = ? "
		+ "ORDER BY created_on DESC, rowid DESC LIMIT 1;", [player_id, buyer_id, window_id])


static func set_state(deal_id: String, state: String, reason: String, date: String,
		detail: String = "") -> bool:
	if deal_id == "" or not available():
		return false
	var ok := PLDatabase.execute(
		"UPDATE deal SET state = ?, reason = ?, updated_on = ?, "
		+ "signed_on = CASE WHEN ? = 'signed' THEN ? ELSE signed_on END, market_day = ? "
		+ "WHERE id = ?;", [state, reason, date, state, date, date, deal_id])
	if ok:
		add_event(deal_id, state, reason, date, detail)
	return ok


static func set_clearance(deal_id: String, due: String) -> bool:
	if deal_id == "" or not available():
		return false
	return PLDatabase.execute("UPDATE deal SET clears_on = ? WHERE id = ?;", [due, deal_id])


static func update_terms(deal_id: String, changes: Dictionary) -> bool:
	var deal := one(deal_id)
	if deal.is_empty():
		return false
	return PLDatabase.execute(
		"UPDATE deal SET fee = ?, wage = ?, years = ?, to_club_id = ?, consent = ?, "
		+ "updated_on = ? WHERE id = ?;",
		[int(changes.get("fee", deal.get("fee", 0))), int(changes.get("wage", deal.get("wage", 0))),
		maxi(int(changes.get("years", deal.get("years", 1))), 1),
		str(changes.get("to_club_id", deal.get("to_club_id", ""))),
		int(changes.get("consent", deal.get("consent", 1))),
		str(changes.get("date", deal.get("updated_on", ""))), deal_id])


static func add_event(deal_id: String, state: String, reason: String, date: String,
		detail: String = "") -> bool:
	if deal_id == "" or not available():
		return false
	return PLDatabase.execute(
		"INSERT INTO deal_event (deal_id, state, reason, on_date, detail) VALUES (?, ?, ?, ?, ?);",
		[deal_id, state, reason, date, detail])


static func timeline(deal_id: String) -> Array:
	if deal_id == "" or not available():
		return []
	return PLDatabase.rows(
		"SELECT * FROM deal_event WHERE deal_id = ? ORDER BY id;", [deal_id])


static func close_contract(player_id: String, club_id: String) -> bool:
	if player_id == "" or club_id == "" or not available():
		return false
	return PLDatabase.execute(
		"UPDATE player_contract SET status = 'transferred' WHERE player_id = ? "
		+ "AND club_id = ? AND status = 'active';", [player_id, club_id])


static func open_contract(player_id: String, club_id: String, date: String, end_date: String,
		wage: int, deal_id: String, season_index: int) -> bool:
	if player_id == "" or club_id == "" or date == "":
		return false
	var start := date
	var guard := 0
	while guard < 8 and not PLDatabase.row(
			"SELECT player_id FROM player_contract WHERE player_id = ? AND start_date = ?;",
			[player_id, start]).is_empty():
		start = FixtureCalendar.add_days(start, 1)
		guard += 1
	var clause := wage * 52 * MarketRules.count("contract", "clause_years", 2)
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_contract (player_id, club_id, season_index, start_date, "
		+ "end_date, wage, signing_bonus, agent_fee, release_clause, option_years, status, "
		+ "deal_id, declined) VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, 0, 'active', ?, 0);",
		[player_id, club_id, season_index, start, end_date, wage, clause, deal_id])


static func close_registration(player_id: String, club_id: String, date: String) -> bool:
	if player_id == "" or club_id == "" or not available():
		return false
	return PLDatabase.execute(
		"UPDATE player_registration SET state = 'closed', to_date = ? WHERE player_id = ? "
		+ "AND club_id = ? AND state IN ('registered', 'pending', 'ineligible');",
		[date, player_id, club_id])


static func open_registration(player_id: String, competition_id: String, club_id: String,
		kind: String, state: String, reason: String, date: String, deal_id: String,
		season_index: int) -> bool:
	if player_id == "" or club_id == "" or date == "":
		return false
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, from_date, to_date, deal_id, season_index) "
		+ "VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?);",
		[player_id, competition_id, club_id, _kind({"kind": kind}), state, reason, date,
		deal_id, season_index])


static func history(player_id: String, club_id: String, competition_id: String, date: String,
		season_index: int) -> bool:
	if player_id == "" or club_id == "" or date == "":
		return false
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_history (player_id, season_index, club_id, "
		+ "competition_id, kind, from_date, to_date) VALUES (?, ?, ?, ?, 'transfer', ?, '');",
		[player_id, season_index, club_id, competition_id, date])


static func move_player(player_id: String, club_id: String) -> int:
	if player_id == "" or club_id == "":
		return 0
	var number := number_for(player_id, club_id)
	if number <= 0:
		return 0
	if not PLDatabase.execute("UPDATE player SET club_id = ?, number = ? WHERE id = ?;",
			[club_id, number, player_id]):
		return 0
	return number


static func number_for(player_id: String, club_id: String) -> int:
	var row := PLDatabase.row("SELECT number FROM player WHERE id = ?;", [player_id])
	if row.is_empty():
		return 0
	var wanted := int(row.get("number", 0))
	var used := {}
	for other in PLDatabase.rows(
			"SELECT number FROM player WHERE club_id = ? AND id <> ?;", [club_id, player_id]):
		used[int(other.get("number", 0))] = true
	if wanted > 0 and not used.has(wanted):
		return wanted
	for number in range(1, 100):
		if not used.has(number):
			return number
	return 99


static func _kind(source: Dictionary) -> String:
	var kind := str(source.get("kind", KIND_PERMANENT))
	return kind if KINDS.has(kind) else KIND_PERMANENT
