class_name LeagueCupPools
extends RefCounted


const META := "cup_pools"
const TOP := {"England": "PL", "Spain": "LL", "Germany": "BL", "Italy": "SA"}
const PAIR := {
	"CS": {"league": "PL", "cup": "FAC", "role": "F"},
	"DFLS": {"league": "BL", "cup": "DFBP", "role": "F"},
	"SCI": {"league": "SA", "cup": "CI", "role": "F"},
}
const UEFA := ["UCL", "UEL", "UECL"]


static func rebuild(season: LeagueSeason, played_index: int, winners: Dictionary,
		runners: Dictionary) -> Dictionary:
	var out := {"ok": false, "countries": [], "entries": {}}
	if season == null or season.save == null or not season.save.ensure_open():
		return out
	if str(season.save.meta.get("cups", "off")) != "on":
		return out
	var entries: Dictionary = {}
	var countries: Array = []
	for country in _active_countries(season.save):
		var top := str(TOP.get(country, ""))
		if top == "" or _places(played_index, top).is_empty():
			continue
		var rows := _rows_for(country, played_index, winners, runners)
		if rows.is_empty():
			continue
		_write(rows)
		countries.append(country)
		for row in rows:
			var cid := str(row["comp"])
			var cell: Dictionary = entries.get(cid, {})
			cell[str(row["club"])] = {"round": str(row["role"]), "source": str(row["source"])}
			entries[cid] = cell
	out["ok"] = true
	out["countries"] = countries
	out["entries"] = entries
	season.save.put_meta(META, JSON.stringify({"season": played_index, "entries": entries}))
	season.save.reload()
	return out


static func reading(save: LeagueSave, competition_id: String) -> Dictionary:
	var parsed: Variant = {} if save == null else JSON.parse_string(str(save.meta.get(META, "{}")))
	if not (parsed is Dictionary):
		return {}
	var rows: Variant = (parsed as Dictionary).get("entries", {})
	if not (rows is Dictionary):
		return {}
	var cell: Variant = (rows as Dictionary).get(competition_id, {})
	return cell if cell is Dictionary else {}


static func field_line(save: LeagueSave, competition_id: String) -> String:
	if LeagueCup.kind(competition_id) != "supercup":
		return ""
	var rows := reading(save, competition_id)
	if rows.is_empty():
		return ""
	var parts: Array = []
	for club_id in _field_order(save, competition_id, rows):
		var row: Dictionary = rows[str(club_id)]
		parts.append("%s · %s" % [LeagueCup.name_of(str(club_id)).to_upper(),
			str(row.get("source", ""))])
	if parts.is_empty():
		return ""
	return "FIELD  " + "  /  ".join(PackedStringArray(parts))


static func _field_order(save: LeagueSave, competition_id: String, rows: Dictionary) -> Array:
	var out: Array = []
	for row in LeagueCup.rounds(competition_id):
		var round_id := str((row as Dictionary).get("id", ""))
		for club_id in LeagueCup.entrants(competition_id, round_id):
			if rows.has(club_id) and not out.has(club_id):
				out.append(club_id)
	for club_id in rows.keys():
		if not out.has(str(club_id)):
			out.append(str(club_id))
	return out


static func _active_countries(save: LeagueSave) -> Array:
	var out: Array = []
	for cid in LeagueCup.active_ids(save):
		var country := str(PLRepository.shared().competition(str(cid)).get("country", ""))
		if country != "" and not out.has(country):
			out.append(country)
	return out


static func _rows_for(country: String, played_index: int, winners: Dictionary,
		runners: Dictionary) -> Array:
	match country:
		"England":
			return _england(played_index, winners, runners)
		"Spain":
			return _spain(played_index, winners, runners)
		"Germany":
			return _germany(played_index, winners, runners)
		"Italy":
			return _italy(played_index, winners, runners)
	return []


static func _england(played_index: int, winners: Dictionary, runners: Dictionary) -> Array:
	var rows: Array = []
	for league_id in ["L1", "L2", "NL"]:
		for club_id in _tier(league_id, played_index):
			rows.append(_row("FAC", club_id, "R1", "TIER"))
	for club_id in _stubs("FAC"):
		rows.append(_row("FAC", club_id, "R1", "STUB SLOT"))
	for league_id in ["PL", "CH"]:
		for club_id in _tier(league_id, played_index):
			rows.append(_row("FAC", club_id, "R3", "TIER"))
	var l2 := _tier("L2", played_index)
	var pr := _tail(l2, 4)
	for club_id in l2:
		rows.append(_row("EFLC", club_id, "PR" if pr.has(club_id) else "R1", "L2 TABLE"))
	for league_id in ["L1", "CH"]:
		for club_id in _tier(league_id, played_index):
			rows.append(_row("EFLC", club_id, "R1", "TIER"))
	var bye := _carabao_bye(played_index)
	for club_id in _tier("PL", played_index):
		rows.append(_row("EFLC", club_id, "R3" if bye.has(club_id) else "R2",
			"EUROPE" if bye.has(club_id) else "PL"))
	rows.append_array(_pair("CS", played_index, winners, runners))
	return rows


static func _spain(played_index: int, winners: Dictionary, runners: Dictionary) -> Array:
	var four := _supercopa(played_index, winners, runners)
	var rows: Array = []
	for club_id in _tier("LL", played_index):
		var late := four.has(club_id)
		rows.append(_row("CDR", club_id, "R32" if late else "R1",
			"SUPERCOPA" if late else "LALIGA"))
	for club_id in _stubs("CDR"):
		var tier := int(PLRepository.shared().club(club_id).get("tier", 4))
		rows.append(_row("CDR", club_id, "PR" if tier >= 5 else "R1", "STUB SLOT"))
	for club_id in four.keys():
		rows.append(_row("SCE", str(club_id), "SF", str(four[club_id])))
	return rows


static func _germany(played_index: int, winners: Dictionary, runners: Dictionary) -> Array:
	var rows: Array = []
	for league_id in ["BL", "BL2"]:
		for club_id in _tier(league_id, played_index):
			rows.append(_row("DFBP", club_id, "R1", "TIER"))
	for club_id in _stubs("DFBP"):
		rows.append(_row("DFBP", club_id, "R1", "STUB SLOT"))
	rows.append_array(_pair("DFLS", played_index, winners, runners))
	return rows


static func _italy(played_index: int, winners: Dictionary, runners: Dictionary) -> Array:
	var rows: Array = []
	var sa := _tier("SA", played_index)
	var seeded := _head(sa, 8)
	for club_id in sa:
		rows.append(_row("CI", club_id, "R16" if seeded.has(club_id) else "R1",
			"SERIE A" if seeded.has(club_id) else "SERIE A R1"))
	var sb := _tier("SB", played_index)
	var low := _tail(sb, 4)
	for club_id in sb:
		rows.append(_row("CI", club_id, "PR" if low.has(club_id) else "R1", "SERIE B"))
	for club_id in _stubs("CI"):
		rows.append(_row("CI", club_id, "PR", "STUB SLOT"))
	rows.append_array(_pair("SCI", played_index, winners, runners))
	return rows


static func _pair(competition_id: String, played_index: int, winners: Dictionary,
		runners: Dictionary) -> Array:
	var spec: Dictionary = PAIR.get(competition_id, {})
	if spec.is_empty():
		return []
	var places := _places(played_index, str(spec["league"]))
	if places.is_empty():
		return []
	var champion := str(places[0])
	var cup := str(spec["cup"])
	var winner := str(winners.get(cup, ""))
	var source := "%s WINNER" % cup
	var other := winner
	if other == "" or other == champion:
		other = str(places[1]) if places.size() > 1 else ""
		if winner == "":
			source = "%s OFF · %s 2ND" % [cup, str(spec["league"])]
		else:
			source = "DOUBLE · %s 2ND" % str(spec["league"])
	if other == "" or other == champion:
		return []
	var role := str(spec["role"])
	return [
		_row(competition_id, champion, role, "%s 1ST" % str(spec["league"])),
		_row(competition_id, other, role, source),
	]


static func _supercopa(played_index: int, winners: Dictionary, runners: Dictionary) -> Dictionary:
	var places := _places(played_index, "LL")
	var out := {}
	var cursor := 0
	var wanted: Array = [
		[str(places[0]) if places.size() > 0 else "", "LALIGA 1ST"],
		[str(places[1]) if places.size() > 1 else "", "LALIGA 2ND"],
		[str(winners.get("CDR", "")), "COPA WINNER"],
		[str(runners.get("CDR", "")), "COPA RUNNER-UP"],
	]
	for cell in wanted:
		var club := str((cell as Array)[0])
		var source := str((cell as Array)[1])
		if club != "" and not out.has(club):
			out[club] = source
			continue
		while cursor < places.size() and out.has(str(places[cursor])):
			cursor += 1
		if cursor >= places.size():
			break
		var fallback := str(places[cursor])
		cursor += 1
		var label := "LALIGA %s" % LeagueEuropeEntries.ordinal(cursor)
		out[fallback] = source if club == "" else source + " · " + label
	return out


static func _carabao_bye(played_index: int) -> Dictionary:
	var need := int((LeagueCup.rules("EFLC").get("entrants", {}) as Dictionary).get("R3", 9))
	var out := {}
	for club_id in _europe_pl():
		out[club_id] = true
	for club_id in _tier("PL", played_index):
		if out.size() >= need:
			break
		out[club_id] = true
	return out


static func _europe_pl() -> Array:
	var out: Array = []
	for cid in UEFA:
		for row in PLDatabase.rows(
				"SELECT member_id FROM competition_member WHERE competition_id = ? "
				+ "AND member_kind = 'club' AND role NOT LIKE 'drop:%';", [cid]):
			var club_id := str(row["member_id"])
			if LeagueUefa.association_of(club_id) != "ENG":
				continue
			if LeaguePyramid.competition_of(club_id) != "PL":
				continue
			if not out.has(club_id):
				out.append(club_id)
	return out


static func _tier(league_id: String, played_index: int) -> Array:
	var present := {}
	for row in PLDatabase.rows(
			"SELECT id, name FROM club WHERE competition_id = ? AND stub = 0;", [league_id]):
		present[str(row["id"])] = str(row["name"])
	var out: Array = []
	for club_id in _places(played_index, league_id):
		if present.has(club_id):
			out.append(club_id)
			present.erase(club_id)
	var rest: Array = present.keys()
	rest.sort_custom(func(a, b): return str(present[a]) < str(present[b]))
	out.append_array(rest)
	return out


static func _places(played_index: int, league_id: String) -> Array:
	var out: Array = []
	for row in SeasonArchive.table(played_index, league_id):
		out.append(str(row["club_id"]))
	return out


static func _stubs(cup_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM club WHERE competition_id = ? AND stub = 1 ORDER BY id;", [cup_id]):
		out.append(str(row["id"]))
	return out


static func _head(clubs: Array, count: int) -> Dictionary:
	var out := {}
	for i in range(mini(count, clubs.size())):
		out[str(clubs[i])] = true
	return out


static func _tail(clubs: Array, count: int) -> Dictionary:
	var out := {}
	var start := maxi(0, clubs.size() - count)
	for i in range(start, clubs.size()):
		out[str(clubs[i])] = true
	return out


static func _row(comp: String, club: String, role: String, source: String) -> Dictionary:
	return {"comp": comp, "club": club, "role": role, "source": source}


static func _write(rows: Array) -> void:
	var cups := {}
	for row in rows:
		cups[str(row["comp"])] = true
	for cid in cups.keys():
		PLDatabase.execute(
			"DELETE FROM competition_member WHERE competition_id = ? AND member_kind = 'club';",
			[str(cid)])
	for row in rows:
		PLDatabase.execute(
			"INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
			+ "VALUES (?, 'club', ?, ?);",
			[str(row["comp"]), str(row["club"]), str(row["role"])])
