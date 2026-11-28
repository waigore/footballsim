class_name MarketDealRecords
extends RefCounted


const TABLE := "deal"
const EVENT_TABLE := "deal_event"
const REGISTRATION := "player_registration"

const PROPOSED := "proposed"
const NEGOTIATING := "negotiating"
const AGREED := "agreed"
const CLEARANCE_PENDING := "clearance_pending"
const SIGNED := "signed"
const WITHDRAWN := "withdrawn"
const FAILED := "failed"
const BLOCKED := "blocked"

const LIVE := [PROPOSED, NEGOTIATING, AGREED, CLEARANCE_PENDING]

const FIELDS := ["id", "kind", "season_index", "state", "from_club_id", "to_club_id", "player_id",
	"fee", "wage", "signing_bonus", "agent_fee", "years", "sell_on", "window_id", "reason",
	"god", "opened_on", "signed_on", "clears_on", "deal_terms"]


static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path:
		return _ready
	_ready_path = path
	_ready = not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'deal';").is_empty()
	return _ready


static func next_id(player_id: String, date: String) -> String:
	var count := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM deal WHERE player_id = ? AND opened_on = ?;",
		[player_id, date]).get("n", 0))
	return "deal:%s:%s:%d" % [player_id, date, count + 1]


static func create(row: Dictionary) -> bool:
	if not available() or str(row.get("id", "")) == "":
		return false
	var marks := PackedStringArray()
	var values: Array = []
	for key in FIELDS:
		marks.append("?")
		values.append(row.get(key, ""))
	if not PLDatabase.execute(
			"INSERT INTO deal (" + ", ".join(PackedStringArray(FIELDS)) + ") VALUES ("
			+ ", ".join(marks) + ");", values):
		return false
	return true


static func load(deal_id: String) -> Dictionary:
	if deal_id == "" or not available():
		return {}
	return PLDatabase.row("SELECT * FROM deal WHERE id = ?;", [deal_id])


static func update(deal_id: String, fields: Dictionary) -> bool:
	if deal_id == "" or fields.is_empty():
		return false
	var sets := PackedStringArray()
	var values: Array = []
	for key in fields:
		if not FIELDS.has(str(key)):
			continue
		sets.append(str(key) + " = ?")
		values.append(fields[key])
	if sets.is_empty():
		return false
	values.append(deal_id)
	return PLDatabase.execute(
		"UPDATE deal SET " + ", ".join(sets) + " WHERE id = ?;", values)


static func set_state(deal_id: String, state: String, date: String, reason: String = "") -> bool:
	var fields := {"state": state, "reason": reason}
	if state == SIGNED:
		fields["signed_on"] = date
	if not update(deal_id, fields):
		return false
	return event(deal_id, date, state, reason)


static func event(deal_id: String, date: String, state: String, reason: String = "") -> bool:
	if deal_id == "" or not available():
		return false
	return PLDatabase.execute(
		"INSERT INTO deal_event (deal_id, date, state, reason) VALUES (?, ?, ?, ?);",
		[deal_id, date, state, reason])


static func events(deal_id: String) -> Array:
	if deal_id == "" or not available():
		return []
	return PLDatabase.rows(
		"SELECT date, state, reason FROM deal_event WHERE deal_id = ? ORDER BY id;", [deal_id])


static func live_for(player_id: String, exclude: String = "") -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM deal WHERE player_id = ? AND state IN ('proposed', 'negotiating', "
		+ "'agreed', 'clearance_pending') AND id <> ? ORDER BY opened_on DESC, id DESC LIMIT 1;",
		[player_id, exclude])


static func last_for(player_id: String) -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM deal WHERE player_id = ? ORDER BY rowid DESC LIMIT 1;", [player_id])


static func vetoed(player_id: String, to_club_id: String, window_id: String) -> bool:
	if player_id == "" or window_id == "" or not available():
		return false
	return not PLDatabase.row(
		"SELECT id FROM deal WHERE player_id = ? AND to_club_id = ? AND window_id = ? "
		+ "AND state = 'blocked' LIMIT 1;", [player_id, to_club_id, window_id]).is_empty()


static func active_contract(player_id: String) -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM player_contract WHERE player_id = ? AND status = 'active' "
		+ "ORDER BY start_date DESC LIMIT 1;", [player_id])


static func registration(player_id: String, competition_id: String) -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM player_registration WHERE player_id = ? AND competition_id = ?;",
		[player_id, competition_id])
