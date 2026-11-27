class_name PLRepository
extends RefCounted


const CANONICAL_ROLES := ["GK", "RB", "RCB", "LCB", "LB", "RDM", "LDM", "RW", "CAM", "LW", "ST"]

static var _shared: PLRepository = null

var _teams := {}
var _players := {}
var _clubs := {}
var _competitions := []

static func shared() -> PLRepository:
	if _shared == null:
		_shared = PLRepository.new()
	return _shared


func invalidate() -> void:
	_teams.clear()
	_players.clear()
	_clubs.clear()
	_competitions.clear()

func meta() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT key, value FROM metadata;"):
		out[str(row["key"])] = str(row["value"])
	return out


func competitions() -> Array:
	if not _competitions.is_empty():
		return _competitions
	var out: Array = []
	for row in PLDatabase.rows("SELECT * FROM competition ORDER BY rowid;"):
		var rules: Variant = row.get("rules", "{}")
		if rules is String:
			var parsed: Variant = JSON.parse_string(str(rules))
			row["rules"] = parsed if parsed is Dictionary else {}
		out.append(row)
	_competitions = out
	return out

func competition(competition_id: String) -> Dictionary:
	for row in competitions():
		if str(row.get("id", "")) == competition_id:
			return row
	return {}


func competition_name(competition_id: String) -> String:
	var row := competition(competition_id)
	return str(row.get("short_name", row.get("name", competition_id)))


func club_ids(competition_id: String = "") -> Array:
	var ids: Array = []
	var sql := "SELECT id FROM club "
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE competition_id = ? "
		bindings.append(competition_id)
	for row in PLDatabase.rows(sql + "ORDER BY name;", bindings):
		ids.append(str(row["id"]))
	return ids


func club(club_id: String) -> Dictionary:
	if _clubs.has(club_id):
		return _clubs[club_id]
	var row := PLDatabase.row("SELECT * FROM club WHERE id = ?;", [club_id])
	if row.is_empty():
		return {}
	var competition_id := str(row.get("competition_id", ""))
	var competition := PLDatabase.row(
		"SELECT name, short_name FROM competition WHERE id = ?;", [competition_id])


	var table: Dictionary = LeagueLedger.club_record(club_id) \
		if PLCompetitions.season_owns(competition_id) \
		else PLDatabase.row("SELECT * FROM table_row WHERE club_id = ?;", [club_id])
	var style := {}
	for key in ["possession", "tempo", "press", "line", "width", "directness", "crossing", "aggression"]:
		style[key] = float(row.get("style_" + key, 0.5))
	var out := {
		"id": str(row["id"]),
		"competition_id": str(row.get("competition_id", "")),
		"name": str(row["name"]),
		"short": str(row["short"]),
		"abbr": str(row["abbr"]),
		"nickname": str(row["nickname"]),
		"competition": competition_id,
		"competition_short": str(competition.get("short_name", competition_id)),
		"competition_name": str(competition.get("name", competition_id)),
		"manager": str(row["manager"]),
		"stadium": str(row["stadium"]),
		"city": str(row["city"]),
		"capacity": int(row["capacity"]),
		"formation": str(row["formation"]),
		"color": Color(str(row["color"])),
		"color_dark": Color(str(row["color_dark"])),
		"color_light": Color(str(row["color_light"])),
		"shorts": Color(str(row["shorts"])),
		"gk_color": Color(str(row["gk_color"])),
		"text": Color(str(row["text_color"])),
		"style": style,
		"table": table,
	}
	_clubs[club_id] = out
	return out


func team(club_id: String) -> Dictionary:
	if _teams.has(club_id):
		return _teams[club_id]
	var base := club(club_id)
	if base.is_empty():
		return {}
	var starters: Array = []
	var bench: Array = []
	for p in squad(club_id):
		var item := {
			"id": p["id"], "name": p["name"], "number": p["number"], "role": p["role"],
			"pos": p["pos"], "ovr": p["ovr"], "pac": p["pac"], "sho": p["sho"],
			"pas": p["pas"], "dri": p["dri"], "def": p["def"], "phy": p["phy"],
			"height": p["height"],
		}
		if str(p["role"]) == "GK":
			item["gk"] = p["gk"]
		if str(p["squad"]) == "bench":
			bench.append(item)
		else:
			starters.append(item)
	var out := base.duplicate()
	out["starters"] = starters
	out["bench"] = bench
	out.erase("table")
	_teams[club_id] = out
	return out


func squad(club_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows("SELECT * FROM player WHERE club_id = ? ORDER BY ord;", [club_id]):
		out.append(_player_row(row))
	return out

func _player_row(row: Dictionary) -> Dictionary:
	var gk := {}
	if row.get("gk_div") != null:
		gk = {
			"div": int(row["gk_div"]), "han": int(row["gk_han"]), "kic": int(row["gk_kic"]),
			"ref": int(row["gk_ref"]), "spd": int(row["gk_spd"]),
		}
	return {
		"id": str(row["id"]), "club_id": str(row["club_id"]), "name": str(row["name"]),
		"number": int(row["number"]), "role": str(row["role"]), "pos": str(row["pos"]),
		"ovr": int(row["ovr"]), "pac": int(row["pac"]), "sho": int(row["sho"]),
		"pas": int(row["pas"]), "dri": int(row["dri"]), "def": int(row["def"]),
		"phy": int(row["phy"]), "height": int(row["height"]), "gk": gk,
		"squad": str(row["squad"]), "age": int(row["age"]), "nationality": str(row["nationality"]),
		"date_of_birth": str(row["date_of_birth"]), "espn_id": str(row["espn_id"]),
	}


func player(player_id: String) -> Dictionary:
	if _players.has(player_id):
		return _players[player_id]
	var row := PLDatabase.row("SELECT * FROM player WHERE id = ?;", [player_id])
	if row.is_empty():
		return {}
	var out := _player_row(row)
	var season := PLDatabase.row("SELECT * FROM season_stat WHERE player_id = ?;", [player_id])
	out["season"] = season
	out["career"] = PLDatabase.row("SELECT * FROM career_stat WHERE player_id = ?;", [player_id])
	out["sim"] = sim_player(player_id)
	_players[player_id] = out
	return out

func player_by_name(club_id: String, name: String) -> Dictionary:
	var row := PLDatabase.row("SELECT id FROM player WHERE club_id = ? AND name = ?;", [club_id, name])
	return player(str(row["id"])) if not row.is_empty() else {}


func table(competition_id: String = "") -> Array:
	if LeagueLedger.bound():


		if competition_id == "" or PLCompetitions.season_owns(competition_id):
			return _live_table(competition_id)
		return []
	return _snapshot_table(competition_id)


func _snapshot_table(competition_id: String = "") -> Array:
	var sql := (
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM table_row t JOIN club c ON c.id = t.club_id "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE c.competition_id = ? "
		bindings.append(competition_id)
	return _placed(PLDatabase.rows(
		sql + "ORDER BY c.competition_id, t.position;", bindings))


func _live_table(competition_id: String = "") -> Array:
	if PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'league_table';"
	).is_empty():
		return []
	var sql := (
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM league_table t JOIN club c ON c.id = t.club_id "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE t.competition_id = ? "
		bindings.append(competition_id)
	return _placed(PLDatabase.rows(
		sql + "ORDER BY t.competition_id, t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;",
		bindings))


func _placed(rows: Array) -> Array:
	var place := 0
	var last := ""
	for i in range(rows.size()):
		var comp := str(rows[i].get("competition_id", ""))
		place = 1 if comp != last else place + 1
		last = comp
		rows[i]["position"] = place
	return rows


func leaders(limit: int = 6, stat: String = "goals", competition_id: String = "") -> Array:
	var column := "assists" if stat == "assists" else "goals"
	var sql := (
		"SELECT s.player_id, s.matches, s.goals, s.assists, p.name, p.pos, c.abbr, "
		+ "c.competition_id FROM season_stat s JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = p.club_id "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE c.competition_id = ? "
		bindings.append(competition_id)
	bindings.append(limit)
	return PLDatabase.rows(
		sql + "ORDER BY s.%s DESC, s.assists DESC, p.name LIMIT ?;" % column, bindings)


func fixtures(club_id: String = "", limit: int = 8, competition_id: String = "") -> Array:
	if LeagueLedger.bound() \
			and (competition_id == "" or PLCompetitions.season_owns(competition_id)):
		return LeagueLedger.fixtures(club_id, limit, competition_id)
	var sql := (
		"SELECT f.*, h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, "
		+ "a.name AS away_name FROM fixture f JOIN club h ON h.id = f.home_club_id "
		+ "JOIN club a ON a.id = f.away_club_id WHERE f.played = 1 "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "AND f.competition_id = ? "
		bindings.append(competition_id)
	if club_id.is_empty():
		return PLDatabase.rows(sql + "ORDER BY f.kickoff DESC LIMIT ?;",
			bindings + [limit])
	sql += "AND (f.home_club_id = ? OR f.away_club_id = ?) "
	sql += "ORDER BY f.kickoff DESC, f.id DESC LIMIT ?;"
	return PLDatabase.rows(sql, bindings + [club_id, club_id, limit])


func upcoming(club_id: String = "", limit: int = 6, competition_id: String = "") -> Array:
	if LeagueLedger.bound() \
			and (competition_id == "" or PLCompetitions.season_owns(competition_id)):
		return LeagueLedger.upcoming(club_id, limit, competition_id)
	var sql := (
		"SELECT f.*, h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, "
		+ "a.name AS away_name FROM fixture f JOIN club h ON h.id = f.home_club_id "
		+ "JOIN club a ON a.id = f.away_club_id WHERE f.played = 0 "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "AND f.competition_id = ? "
		bindings.append(competition_id)
	if club_id.is_empty():
		return PLDatabase.rows(sql + "ORDER BY f.kickoff ASC, f.id ASC LIMIT ?;",
			bindings + [limit])
	sql += "AND (f.home_club_id = ? OR f.away_club_id = ?) ORDER BY f.kickoff ASC, f.id ASC LIMIT ?;"
	return PLDatabase.rows(sql, bindings + [club_id, club_id, limit])


func season_active() -> bool:
	return LeagueLedger.bound()


func sim_player(player_id: String) -> Dictionary:
	if LeagueLedger.bound():
		return LeagueLedger.player_line(player_id)
	return PLDatabase.row("SELECT * FROM sim_player_stat WHERE player_id = ?;", [player_id])


func sim_club(club_id: String) -> Dictionary:
	if LeagueLedger.bound():
		return LeagueLedger.club_record(club_id)
	return PLDatabase.row("SELECT * FROM sim_club_stat WHERE club_id = ?;", [club_id])


func sim_scorers(club_id: String, limit: int = 5) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.scorers(club_id, limit)
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id FROM sim_player_stat s "
		+ "JOIN player p ON p.id = s.player_id WHERE p.club_id = ? AND s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;",
		[club_id, limit],
	)


func sim_leaders(limit: int = 5, competition_id: String = "", stat: String = "goals",
		teams: Array = []) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.leaders(limit, competition_id, stat, teams)
	var column := "assists" if stat == "assists" else "goals"
	var sql := (
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr, "
		+ "c.id AS club_id, c.competition_id FROM sim_player_stat s "
		+ "JOIN player p ON p.id = s.player_id JOIN club c ON c.id = p.club_id WHERE s.%s > 0" % column
	)
	var bindings: Array = []
	if competition_id != "":
		sql += " AND c.competition_id = ?"
		bindings.append(competition_id)
	if not teams.is_empty():
		var marks := PackedStringArray()
		for i in range(teams.size()):
			marks.append("?")
		sql += " AND c.id IN (" + ",".join(marks) + ")"
		bindings.append_array(teams)
	sql += " ORDER BY s.%s DESC, s.assists DESC, p.name LIMIT ?;" % column
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)
