class_name MarketLoanRecords
extends RefCounted


const TABLE := "player_loan"
const ACTIVE := "active"
const RETURNED := "returned"
const CONVERTED := "converted"

const FIELDS := ["id", "player_id", "parent_club_id", "loanee_club_id", "season_index",
	"start_date", "end_date", "wage_parent", "wage_loanee", "fee", "option_kind", "buy_fee",
	"trigger_kind", "trigger_value", "status", "deal_id", "returned_on"]

static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path and path != "":
		return _ready
	_ready_path = path
	_ready = path != "" and not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'player_loan';").is_empty()
	return _ready


static func create(row: Dictionary) -> bool:
	if not available() or str(row.get("id", "")) == "":
		return false
	var marks := PackedStringArray()
	var values: Array = []
	for key in FIELDS:
		marks.append("?")
		values.append(row.get(key, ""))
	return PLDatabase.execute(
		"INSERT INTO player_loan (" + ", ".join(PackedStringArray(FIELDS)) + ") VALUES ("
		+ ", ".join(marks) + ");", values)


static func load(loan_id: String) -> Dictionary:
	if loan_id == "" or not available():
		return {}
	return PLDatabase.row("SELECT * FROM player_loan WHERE id = ?;", [loan_id])


static func update(loan_id: String, fields: Dictionary) -> bool:
	if loan_id == "" or fields.is_empty() or not available():
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
	values.append(loan_id)
	return PLDatabase.execute(
		"UPDATE player_loan SET " + ", ".join(sets) + " WHERE id = ?;", values)


static func active_for(player_id: String) -> Dictionary:
	if player_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM player_loan WHERE player_id = ? AND status = 'active' "
		+ "ORDER BY start_date DESC LIMIT 1;", [player_id])


static func all_active() -> Array:
	if not available():
		return []
	return PLDatabase.rows(
		"SELECT * FROM player_loan WHERE status = 'active' ORDER BY end_date, id;")


static func count_out(parent_club_id: String, season_index: int, exclude: String = "") -> int:
	if parent_club_id == "" or not available():
		return 0
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_loan WHERE parent_club_id = ? AND season_index = ? "
		+ "AND id <> ?;", [parent_club_id, season_index, exclude]).get("n", 0))


static func count_in(loanee_club_id: String, season_index: int, exclude: String = "") -> int:
	if loanee_club_id == "" or not available():
		return 0
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_loan WHERE loanee_club_id = ? AND season_index = ? "
		+ "AND id <> ?;", [loanee_club_id, season_index, exclude]).get("n", 0))


static func count_pair(parent_club_id: String, loanee_club_id: String, season_index: int,
		exclude: String = "") -> int:
	if parent_club_id == "" or loanee_club_id == "" or not available():
		return 0
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM player_loan WHERE parent_club_id = ? AND loanee_club_id = ? "
		+ "AND season_index = ? AND id <> ?;",
		[parent_club_id, loanee_club_id, season_index, exclude]).get("n", 0))
