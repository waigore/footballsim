class_name SquadList
extends RefCounted


const TABLE := "player_registration"
const UEFA_IDS := ["UCL", "UEL", "UECL"]

const REGISTERED := "registered"
const PROVISIONAL := "provisional"
const INELIGIBLE := "ineligible"
const PENDING := "pending"
const CLOSED := "closed"

const FULL := "list_full"

const NATIONS := {
	"ENG": ["England", "ENG"],
	"ESP": ["Spain", "ESP"],
	"GER": ["Germany", "GER"],
	"ITA": ["Italy", "ITA"],
}

static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path:
		return _ready
	_ready_path = path
	_ready = not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?;",
		[TABLE]).is_empty()
	return _ready


static func rule() -> Dictionary:
	var list := MarketRules.section("list")
	var uefa: Variant = list.get("uefa", {})
	return uefa if uefa is Dictionary else {}


static func slots() -> int:
	return int(rule().get("slots", 25))


static func trained_min() -> int:
	return int(rule().get("trained_min", 4))


static func u21_free() -> bool:
	return int(rule().get("u21_free", 1)) == 1


static func is_uefa(competition_id: String) -> bool:
	return PLRepository.shared().competition_kind(competition_id) == "continental"


static func entries(club_id: String) -> Array:
	var out: Array = []
	if club_id == "":
		return out
	var rows := PLDatabase.rows(
		"SELECT competition_id FROM competition_member WHERE member_kind = 'club' "
		+ "AND member_id = ?;", [club_id])
	var present := {}
	for row in rows:
		present[str(row["competition_id"])] = true
	for cid in UEFA_IDS:
		if present.has(str(cid)) and is_uefa(str(cid)):
			out.append(str(cid))
	return out


static func association(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("country", ""))


static func trained(player_id: String, club_id: String) -> bool:
	var player := PLDatabase.row("SELECT nationality FROM player WHERE id = ?;", [player_id])
	if player.is_empty():
		return false
	var nations: Variant = NATIONS.get(association(club_id), [])
	return (nations as Array).has(str(player.get("nationality", "")))


static func exempt(player_id: String) -> bool:
	if not u21_free():
		return false
	var age := int(PLDatabase.row("SELECT age FROM player WHERE id = ?;",
		[player_id]).get("age", 0))
	return age > 0 and age < 21


static func slots_used(club_id: String, competition_id: String,
		exclude_player: String = "") -> int:
	var count := 0
	for row in rows(club_id, competition_id):
		if str(row.get("state", "")) == CLOSED:
			continue
		if str(row.get("player_id", "")) == exclude_player:
			continue
		if exempt(str(row["player_id"])):
			continue
		count += 1
	return count


static func trained_count(club_id: String, competition_id: String) -> int:
	var count := 0
	for row in rows(club_id, competition_id):
		if str(row.get("state", "")) == CLOSED:
			continue
		if trained(str(row["player_id"]), club_id):
			count += 1
	return count


static func verdict(club_id: String, competition_id: String, player_id: String) -> Dictionary:
	if not is_uefa(competition_id) or club_id == "" or player_id == "":
		return pass_with("")
	if exempt(player_id):
		return pass_with("u21")
	if slots_used(club_id, competition_id, player_id) >= slots():
		return fail(FULL, "the UEFA list is full")
	return pass_with("")


static func register(club_id: String, competition_id: String, player_id: String,
		state: String, reason: String = "", deal_id: String = "",
		season_index: int = 0, kind: String = "permanent") -> bool:
	if not available() or player_id == "" or competition_id == "":
		return false
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index) VALUES (?, ?, ?, ?, ?, ?, ?, ?);",
		[player_id, competition_id, club_id, kind, state, reason, deal_id, season_index])


static func rows(club_id: String, competition_id: String) -> Array:
	if not available() or club_id == "" or competition_id == "":
		return []
	return PLDatabase.rows(
		"SELECT * FROM player_registration WHERE club_id = ? AND competition_id = ? "
		+ "ORDER BY player_id;", [club_id, competition_id])


static func state_of(player_id: String, competition_id: String) -> String:
	if not available() or player_id == "" or competition_id == "":
		return ""
	return str(PLDatabase.row(
		"SELECT state FROM player_registration WHERE player_id = ? AND competition_id = ?;",
		[player_id, competition_id]).get("state", ""))


static func ineligible_ids(club_id: String, competition_id: String) -> Array:
	var out: Array = []
	if not is_uefa(competition_id):
		return out
	for row in rows(club_id, competition_id):
		if [INELIGIBLE, PENDING].has(str(row.get("state", ""))):
			out.append(str(row["player_id"]))
	return out


static func bootstrap(save: LeagueSave) -> Dictionary:
	var out := {"ok": false, "lists": 0, "players": 0, "provisional": 0, "skipped": false}
	if save == null or not save.ensure_open():
		return out
	if not available() or str(save.meta.get("uefa", "off")) != "on":
		return out
	var index := save.season_index()
	if int(PLDatabase.row(
			"SELECT COUNT(*) AS n FROM player_registration WHERE season_index = ?;",
			[index]).get("n", 0)) > 0:
		out["ok"] = true
		out["skipped"] = true
		return out
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for cid in UEFA_IDS:
		var list := _bootstrap_competition(str(cid), index)
		out["lists"] = int(out["lists"]) + 1
		out["players"] = int(out["players"]) + int(list.get("players", 0))
		out["provisional"] = int(out["provisional"]) + int(list.get("provisional", 0))
	PLDatabase.transaction("COMMIT;")
	out["ok"] = true
	return out


static func reading(club_id: String, competition_id: String) -> Dictionary:
	if not is_uefa(competition_id):
		return {}
	var present := rows(club_id, competition_id)
	if present.is_empty():
		return {}
	var players: Array = []
	for row in present:
		var player_id := str(row["player_id"])
		var player := PLDatabase.row("SELECT name, pos, nationality, age FROM player WHERE id = ?;",
			[player_id])
		if player.is_empty():
			continue
		players.append({
			"id": player_id,
			"name": str(player.get("name", player_id)),
			"pos": str(player.get("pos", "")),
			"state": str(row.get("state", "")),
			"reason": str(row.get("reason", "")),
			"trained": trained(player_id, club_id),
			"exempt": exempt(player_id),
		})
	return {
		"competition": competition_id,
		"name": str(PLRepository.shared().competition_name(competition_id)),
		"slots": slots(),
		"slots_used": slots_used(club_id, competition_id),
		"trained": trained_count(club_id, competition_id),
		"trained_min": trained_min(),
		"state": list_state(club_id, competition_id),
		"players": players,
	}


static func list_state(club_id: String, competition_id: String) -> String:
	if slots_used(club_id, competition_id) > slots():
		return PROVISIONAL
	return REGISTERED


static func _bootstrap_competition(competition_id: String, season_index: int) -> Dictionary:
	var out := {"players": 0, "provisional": 0}
	if not is_uefa(competition_id):
		return out
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' ORDER BY member_id;", [competition_id]):
		var club_id := str(row["member_id"])
		var squad := _squad_for(club_id)
		for player_id in squad:
			if register(club_id, competition_id, str(player_id), REGISTERED, "", "", season_index):
				out["players"] = int(out["players"]) + 1
		if list_state(club_id, competition_id) == PROVISIONAL:
			PLDatabase.execute(
				"UPDATE player_registration SET state = ? WHERE club_id = ? "
				+ "AND competition_id = ? AND state = ?;",
				[PROVISIONAL, club_id, competition_id, REGISTERED])
			out["provisional"] = int(out["provisional"]) + 1
	return out


static func _squad_for(club_id: String) -> Array:
	var club := PLDatabase.row("SELECT stub FROM club WHERE id = ?;", [club_id])
	var out: Array = []
	if int(club.get("stub", 0)) == 1:
		for row in PLDatabase.rows(
				"SELECT id FROM player WHERE club_id = ? ORDER BY squad = 'starter' DESC, ord, id "
				+ "LIMIT 11;", [club_id]):
			out.append(str(row["id"]))
		return out
	for row in PLDatabase.rows("SELECT id FROM player WHERE club_id = ? ORDER BY ord;", [club_id]):
		out.append(str(row["id"]))
	return out


static func pass_with(note: String) -> Dictionary:
	return {"ok": true, "code": "", "detail": note}


static func fail(code: String, detail: String) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail}
