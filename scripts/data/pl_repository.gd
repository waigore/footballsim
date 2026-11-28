class_name PLRepository
extends "res://scripts/data/pl_repository_season.gd"


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


func leagues() -> Array:
	var out: Array = []
	for row in competitions():
		var rules: Dictionary = row.get("rules", {})
		if str(rules.get("kind", "league")) == "league":
			out.append(row)
	return out


func cups() -> Array:
	var out: Array = []
	for row in competitions():
		var rules: Dictionary = row.get("rules", {})
		if str(rules.get("kind", "league")) != "league":
			out.append(row)
	return out


func competition_kind(competition_id: String) -> String:
	var rules: Dictionary = competition(competition_id).get("rules", {})
	return str(rules.get("kind", "league"))


func competition_name(competition_id: String) -> String:
	var row := competition(competition_id)
	return str(row.get("short_name", row.get("name", competition_id)))


func club_ids(competition_id: String = "") -> Array:
	var ids: Array = []
	if competition_id == "":
		for row in leagues():
			ids.append_array(club_ids(str(row["id"])))
		ids.sort()
		return ids
	for row in PLDatabase.rows(
		"SELECT id FROM club WHERE competition_id = ? ORDER BY name;", [competition_id]):
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
		"country": str(row.get("country", "")),
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
		"subs": _json_field(row.get("subs")),
		"extras": _json_field(row.get("extras")),
		"ratings_matched": int(row.get("ratings_matched", 0)) == 1,
	}


static func _json_field(raw: Variant) -> Dictionary:
	if raw is Dictionary:
		return raw
	if raw == null or str(raw) == "":
		return {}
	var parsed: Variant = JSON.parse_string(str(raw))
	return parsed if parsed is Dictionary else {}


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
