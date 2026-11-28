class_name PositionRace
extends RefCounted


const MIN_DAYS := 2


static func series(club_id: String) -> Dictionary:
	var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	var competition := str(club.get("competition_id", ""))
	if competition == "":
		return {}
	var clubs := _clubs(competition)
	if clubs.size() < 2:
		return {}
	var days := _days(competition)
	if days.size() < MIN_DAYS:
		return {}
	var rules := _rules(competition)
	var acc := {}
	for id in clubs.keys():
		acc[id] = {"name": str(clubs[id]), "points": 0, "gf": 0, "ga": 0}
	var path: Array = []
	var best := 0
	var worst := 0
	for day in days:
		for fx in day["fixtures"]:
			_apply(acc, fx, rules)
		var place: int = _order(acc).find(club_id) + 1
		if place < 1:
			return {}
		path.append({"date": str(day["date"]), "position": place})
		best = place if best == 0 else mini(best, place)
		worst = maxi(worst, place)
	if path.size() < MIN_DAYS:
		return {}
	return {
		"club": club_id, "competition": competition, "clubs": clubs.size(),
		"days": path, "best": best, "worst": worst,
		"place": int((path[path.size() - 1] as Dictionary)["position"]),
	}


static func _clubs(competition: String) -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT id, name FROM club WHERE competition_id = ?;", [competition]):
		out[str(row["id"])] = str(row["name"])
	for row in _played(competition):
		for key in ["home_club_id", "away_club_id"]:
			var id := str(row[key])
			if out.has(id):
				continue
			var named := PLDatabase.row("SELECT name FROM club WHERE id = ?;", [id])
			out[id] = str(named.get("name", id))
	return out


static func _played(competition: String) -> Array:
	if LeagueLedger.bound():
		return PLDatabase.rows(
			"SELECT home_club_id, away_club_id, home_goals, away_goals, kickoff, kickoff_time "
			+ "FROM league_fixture WHERE competition_id = ? AND status = 'played' "
			+ "ORDER BY kickoff, kickoff_time, id;", [competition])
	return PLDatabase.rows(
		"SELECT home_club_id, away_club_id, home_goals, away_goals, kickoff, '' AS kickoff_time "
		+ "FROM fixture WHERE competition_id = ? AND played = 1 ORDER BY kickoff, id;",
		[competition])


static func _days(competition: String) -> Array:
	var by_date := {}
	var order: Array = []
	for fx in _played(competition):
		var date := str(fx["kickoff"]).substr(0, 10)
		if not by_date.has(date):
			by_date[date] = []
			order.append(date)
		(by_date[date] as Array).append(fx)
	var out: Array = []
	for date in order:
		out.append({"date": date, "fixtures": by_date[date]})
	return out


static func _rules(competition: String) -> Dictionary:
	var row := PLDatabase.row("SELECT rules FROM competition WHERE id = ?;", [competition])
	var raw: Variant = row.get("rules", "{}")
	if raw is Dictionary:
		return raw
	if raw is String:
		var parsed: Variant = JSON.parse_string(str(raw))
		if parsed is Dictionary:
			return parsed
	return {}


static func _apply(acc: Dictionary, fx: Dictionary, rules: Dictionary) -> void:
	_tally(acc, str(fx["home_club_id"]), int(fx["home_goals"]), int(fx["away_goals"]), rules)
	_tally(acc, str(fx["away_club_id"]), int(fx["away_goals"]), int(fx["home_goals"]), rules)


static func _tally(acc: Dictionary, club_id: String, gf: int, ga: int, rules: Dictionary) -> void:
	if not acc.has(club_id):
		return
	var s: Dictionary = acc[club_id]
	s["points"] = int(s["points"]) + LeagueRules.points(gf, ga, rules)
	s["gf"] = int(s["gf"]) + gf
	s["ga"] = int(s["ga"]) + ga


static func _order(acc: Dictionary) -> Array:
	var rows: Array = []
	for id in acc.keys():
		var s: Dictionary = acc[id]
		rows.append({
			"id": str(id), "name": str(s["name"]), "points": int(s["points"]),
			"gd": int(s["gf"]) - int(s["ga"]), "gf": int(s["gf"]),
		})
	rows.sort_custom(_before)
	var out: Array = []
	for row in rows:
		out.append(str(row["id"]))
	return out


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if int(a["points"]) != int(b["points"]):
		return int(a["points"]) > int(b["points"])
	if int(a["gd"]) != int(b["gd"]):
		return int(a["gd"]) > int(b["gd"])
	if int(a["gf"]) != int(b["gf"]):
		return int(a["gf"]) > int(b["gf"])
	return str(a["name"]) < str(b["name"])
