class_name MarketLists
extends RefCounted


const SLOTS := 25
const HOMEGROWN_MIN := 8


static func slots_used(club_id: String, competition_id: String = "") -> int:
	if club_id == "":
		return 0
	var sql := ("SELECT COUNT(*) AS n FROM player_registration r "
		+ "JOIN player p ON p.id = r.player_id "
		+ "WHERE r.club_id = ? AND r.state <> 'closed' "
		+ "AND (p.age IS NULL OR p.age = 0 OR p.age >= 21) AND r.u21_exempt = 0")
	var bindings: Array = [club_id]
	if competition_id != "":
		sql += " AND r.competition_id = ?"
		bindings.append(competition_id)
	return int(PLDatabase.row(sql + ";", bindings).get("n", 0))


static func homegrown(club_id: String, competition_id: String = "") -> int:
	if club_id == "":
		return 0
	var sql := ("SELECT COUNT(*) AS n FROM player_registration r "
		+ "JOIN player p ON p.id = r.player_id "
		+ "WHERE r.club_id = ? AND r.state <> 'closed' AND p.homegrown_club_id = r.club_id")
	var bindings: Array = [club_id]
	if competition_id != "":
		sql += " AND r.competition_id = ?"
		bindings.append(competition_id)
	return int(PLDatabase.row(sql + ";", bindings).get("n", 0))


static func player_exempt(player_id: String) -> bool:
	if player_id == "":
		return false
	if int(PLDatabase.row(
			"SELECT u21_exempt FROM player_registration WHERE player_id = ? "
			+ "ORDER BY u21_exempt DESC LIMIT 1;", [player_id]).get("u21_exempt", 0)) == 1:
		return true
	var age := int(PLDatabase.row("SELECT age FROM player WHERE id = ?;", [player_id]).get(
		"age", 0))
	return age > 0 and age < 21


static func registrable(player_id: String, club_id: String, competition_id: String) -> Dictionary:
	if player_id == "" or club_id == "":
		return {"ok": false, "code": "list_full", "detail": "no player or club"}
	if player_exempt(player_id):
		return {"ok": true, "code": "ok", "detail": "u21_exempt"}
	var used := slots_used(club_id, competition_id)
	if used >= SLOTS:
		return {"ok": false, "code": "list_full",
			"detail": "the list holds %d of %d slots" % [used, SLOTS]}
	return {"ok": true, "code": "ok", "detail": "%d of %d slots" % [used + 1, SLOTS]}


static func list_reading(club_id: String, competition_id: String = "") -> Dictionary:
	return {
		"used": slots_used(club_id, competition_id),
		"slots": SLOTS,
		"homegrown": homegrown(club_id, competition_id),
		"homegrown_min": HOMEGROWN_MIN,
	}
