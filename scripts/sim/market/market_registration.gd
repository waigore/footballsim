class_name MarketRegistration
extends RefCounted


const TABLE := "player_registration"
const REGISTERED := "registered"
const PROVISIONAL := "provisional"
const INELIGIBLE := "ineligible"
const CLOSED := "closed"

const OK := "ok"
const PERMIT := "permit"


static var _ready_path := ""
static var _ready := false


static func available() -> bool:
	var path := PLDatabase.current_path()
	if path == _ready_path:
		return _ready
	_ready_path = path
	_ready = not PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'player_registration';").is_empty()
	return _ready


static func row(player_id: String, competition_id: String) -> Dictionary:
	if player_id == "" or competition_id == "" or not available():
		return {}
	return PLDatabase.row(
		"SELECT * FROM player_registration WHERE player_id = ? AND competition_id = ?;",
		[player_id, competition_id])


static func rows_of(club_id: String, competition_id: String) -> Array:
	if club_id == "" or competition_id == "" or not available():
		return []
	return PLDatabase.rows(
		"SELECT r.*, p.name AS player_name, p.nationality AS nationality, p.age AS age, "
		+ "p.ovr AS ovr, p.role AS role FROM player_registration r "
		+ "JOIN player p ON p.id = r.player_id "
		+ "WHERE r.club_id = ? AND r.competition_id = ? AND r.state <> 'closed' "
		+ "ORDER BY p.ord, p.id;", [club_id, competition_id])


static func selectable(player_id: String, competition_id: String) -> bool:
	if player_id == "":
		return true
	var found := row(player_id, competition_id)
	if found.is_empty():
		return true
	var state := str(found.get("state", ""))
	return state != INELIGIBLE


static func ineligible_ids(club_id: String, competition_id: String) -> Dictionary:
	var out := {}
	if club_id == "" or competition_id == "" or not available():
		return out
	for found in PLDatabase.rows(
			"SELECT player_id FROM player_registration WHERE club_id = ? AND competition_id = ? "
			+ "AND state = 'ineligible';", [club_id, competition_id]):
		out[str(found["player_id"])] = true
	return out


static func declare(club_id: String, competition_id: String) -> Dictionary:
	if club_id == "" or competition_id == "" or not available():
		return {"ok": false, "code": "no_save"}
	var index := LeagueSave.current.season_index() if LeagueSave.current != null else 0
	var written := 0
	var ineligible := 0
	var rejected: Array = []
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for found in PLDatabase.rows(
			"SELECT p.id FROM player p JOIN player_contract c ON c.player_id = p.id "
			+ "AND c.status = 'active' AND c.club_id = p.club_id "
			+ "WHERE p.club_id = ? ORDER BY p.ord, p.id;", [club_id]):
		var player_id := str(found["id"])
		if not row(player_id, competition_id).is_empty():
			written += 1
			continue
		var verdict := register(player_id, club_id, competition_id, "permanent", "", index)
		if not bool(verdict.get("ok", false)):
			rejected.append({"player": player_id, "code": str(verdict.get("code", ""))})
			continue
		written += 1
		if str(verdict.get("state", "")) == INELIGIBLE:
			ineligible += 1
	PLDatabase.transaction("COMMIT;")
	return {"ok": not row(_first_player(club_id), competition_id).is_empty(),
		"registered": written, "ineligible": ineligible,
		"state": state_of(club_id, competition_id), "rejected": rejected,
		"counts": tally(club_id, competition_id)}


static func _first_player(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ord, id LIMIT 1;",
		[club_id]).get("id", ""))


static func declare_entrants(save: LeagueSave) -> Dictionary:
	if save == null or not save.ensure_open() or not available():
		return {"ok": false, "reason": "no_save"}
	var declared := 0
	var provisional := 0
	for competition_id in LeagueUefa.active_ids(save):
		for found in PLDatabase.rows(
				"SELECT m.member_id AS id FROM competition_member m JOIN club c ON c.id = m.member_id "
				+ "WHERE m.competition_id = ? AND m.member_kind = 'club' AND c.stub = 0 "
				+ "GROUP BY m.member_id ORDER BY m.member_id;", [str(competition_id)]):
			var out := declare(str(found["id"]), str(competition_id))
			declared += 1
			if str(out.get("state", "")) == PROVISIONAL:
				provisional += 1
	return {"ok": true, "declared": declared, "provisional": provisional}


static func player_of(player_id: String) -> Dictionary:
	if player_id == "":
		return {}
	return PLDatabase.row(
		"SELECT id, club_id, nationality, age, ovr, role, homegrown_club_id "
		+ "FROM player WHERE id = ?;", [player_id])


static func tally(club_id: String, competition_id: String) -> Dictionary:
	var club := PLDatabase.row("SELECT id, competition_id, country FROM club WHERE id = ?;",
		[club_id])
	var association := MarketEligibility.association_of_club(club)
	var players: Array = []
	for found in rows_of(club_id, competition_id):
		players.append({
			"nationality": str(found.get("nationality", "")),
			"age": int(found.get("age", 0)),
			"homegrown_club_id": str(found.get("homegrown_club_id", "")),
		})
	var out := MarketEligibility.tally(players, club_id, competition_id, association)
	out["association_code"] = association
	out["competition_id"] = competition_id
	return out


static func state_of(club_id: String, competition_id: String) -> String:
	var counts := tally(club_id, competition_id)
	if (MarketEligibility.bands(competition_id, str(counts.get("association_code", "")),
			counts) as Array).is_empty():
		return REGISTERED
	return PROVISIONAL


static func admit(player_id: String, club_id: String, competition_id: String) -> Dictionary:
	var player := player_of(player_id)
	if player.is_empty():
		return {"ok": false, "code": "no_player"}
	var club := PLDatabase.row("SELECT id, competition_id, country FROM club WHERE id = ?;",
		[club_id])
	if club.is_empty():
		return {"ok": false, "code": "no_club"}
	if MarketFFP.embargoed(club_id):
		return {"ok": false, "code": MarketDealRules.FFP}
	var association := MarketEligibility.association_of_club(club)
	var counts := tally(club_id, competition_id)
	var reasons := MarketEligibility.admits(competition_id, association, counts, {
		"nationality": str(player.get("nationality", "")),
		"age": int(player.get("age", 0)),
		"homegrown_club_id": str(player.get("homegrown_club_id", "")),
		"club_id": club_id,
	})
	if not reasons.is_empty():
		return {"ok": false, "code": str(reasons[0]), "reasons": reasons}
	return {"ok": true, "code": OK, "counts": counts}


static func permit(player_id: String, club_id: String) -> Dictionary:
	var player := player_of(player_id)
	if player.is_empty():
		return {"ok": false, "state": INELIGIBLE, "reason": PERMIT}
	var club := PLDatabase.row("SELECT id, competition_id, country FROM club WHERE id = ?;",
		[club_id])
	var association := MarketEligibility.association_of_club(club)
	var nationality := str(player.get("nationality", ""))
	if association == "" or not MarketEligibility.is_non_eu(nationality, association):
		return {"ok": true, "state": OK, "reason": ""}
	var threshold := MarketEligibility.permit_threshold(association)
	if threshold <= 0 or int(player.get("ovr", 0)) >= threshold:
		return {"ok": true, "state": OK, "reason": ""}
	return {"ok": false, "state": INELIGIBLE, "reason": PERMIT}


static func register(player_id: String, club_id: String, competition_id: String,
		kind: String = "permanent", deal_id: String = "", season_index: int = 0,
		date: String = "", free_agent: bool = false) -> Dictionary:
	if not available():
		return {"ok": false, "code": "no_save"}
	var club := PLDatabase.row("SELECT id, competition_id, country FROM club WHERE id = ?;",
		[club_id])
	if club.is_empty():
		return {"ok": false, "code": "no_club"}
	if date != "" and not free_agent:
		var country := MarketEligibility.association_of_club(club)
		if MarketWindows.open_window(date, country).is_empty():
			return {"ok": false, "code": MarketDealRules.WINDOW_CLOSED}
	var verdict := admit(player_id, club_id, competition_id)
	if not bool(verdict.get("ok", false)):
		return verdict
	var player := player_of(player_id)
	var homegrown := str(player.get("homegrown_club_id", ""))
	var association := MarketEligibility.association_of_club(club)
	var gate := permit(player_id, club_id)
	if not bool(gate.get("ok", false)):
		write(player_id, competition_id, club_id, kind, INELIGIBLE, PERMIT, deal_id,
			season_index, homegrown, association, INELIGIBLE, PERMIT)
		return {"ok": true, "code": OK, "state": INELIGIBLE, "reason": PERMIT}
	write(player_id, competition_id, club_id, kind, REGISTERED, "", deal_id, season_index,
		homegrown, association, OK, "")
	return {"ok": true, "code": OK, "state": REGISTERED, "reason": ""}


static func verify(player_id: String, club_id: String, competition_id: String,
		kind: String, deal_id: String = "", season_index: int = -1) -> String:
	var player := player_of(player_id)
	var homegrown := str(player.get("homegrown_club_id", ""))
	if homegrown == "":
		homegrown = club_id if not player.is_empty() else ""
	var index := season_index
	if index < 0:
		index = LeagueSave.current.season_index() if LeagueSave.current != null else 0
	var club_row := PLDatabase.row(
		"SELECT id, competition_id, country FROM club WHERE id = ?;", [club_id])
	var association := MarketEligibility.association_of_club(club_row)
	write(player_id, competition_id, club_id, kind, REGISTERED, "", deal_id, index,
		homegrown, association, OK, "")
	return REGISTERED


static func write(player_id: String, competition_id: String, club_id: String, kind: String,
		state: String, reason: String, deal_id: String, season_index: int,
		homegrown_club_id: String, association: String, permit_state: String,
		permit_reason: String) -> bool:
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index, homegrown_club_id, association, permit_state, "
		+ "permit_reason) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
		[player_id, competition_id, club_id, kind, state, reason, deal_id, season_index,
		 homegrown_club_id, association, permit_state, permit_reason])


static func close(player_id: String, club_id: String, deal_id: String = "") -> int:
	if player_id == "" or club_id == "" or not available():
		return 0
	PLDatabase.execute(
		"UPDATE player_registration SET state = 'closed', reason = 'moved', deal_id = ? "
		+ "WHERE club_id = ? AND player_id = ? AND state <> 'closed';",
		[deal_id, club_id, player_id])
	return 1


static func bootstrap(save: LeagueSave) -> Dictionary:
	if save == null or not save.ensure_open() or not available():
		return {"ok": false, "reason": "no_save"}
	var domestic: Array = LeagueTiers.order()
	var marks := PackedStringArray()
	for i in range(domestic.size()):
		marks.append("?")
	if int(PLDatabase.row(
			"SELECT COUNT(*) AS n FROM player_registration WHERE competition_id IN ("
			+ ", ".join(marks) + ");", domestic).get("n", 0)) > 0:
		return {"ok": true, "skipped": true, "registered": 0, "provisional": 0}
	return auto_register(save)


static func auto_register(save: LeagueSave) -> Dictionary:
	var index := save.season_index() if save != null else 0
	var written := 0
	var provisional := 0
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for club in PLDatabase.rows(
			"SELECT id, competition_id FROM club WHERE stub = 0 "
			+ "AND competition_id <> '' ORDER BY id;"):
		var club_id := str(club["id"])
		var competition_id := str(club.get("competition_id", ""))
		if not MarketEligibility.is_domestic(competition_id):
			continue
		for player in PLDatabase.rows(
				"SELECT id FROM player WHERE club_id = ? ORDER BY ord, id;", [club_id]):
			verify(str(player["id"]), club_id, competition_id, "permanent", "", index)
			written += 1
		if state_of(club_id, competition_id) == PROVISIONAL:
			provisional += 1
	PLDatabase.transaction("COMMIT;")
	return {"ok": true, "registered": written, "provisional": provisional}
