class_name LeagueEuropeEntries
extends RefCounted


const META := "uefa_entries"
const CUP_NAMES := {
	"FAC": "FA CUP", "EFLC": "LEAGUE CUP", "CDR": "COPA DEL REY",
	"DFBP": "DFB POKAL", "CI": "COPPA ITALIA",
}
const LEAGUE_NAMES := {
	"ENG": "PL", "ESP": "LALIGA", "GER": "BUNDESLIGA", "ITA": "SERIE A",
}


static func published(competition_id: String) -> bool:
	var access: Variant = LeagueUefa.rules(competition_id).get("access", {})
	return access is Dictionary and not (access as Dictionary).is_empty()


static func regenerate(season: LeagueSeason, played_index: int, cups: Dictionary) -> Dictionary:
	var out := {"ok": false, "carried": [], "entries": {}}
	if season == null or season.save == null or not season.save.ensure_open():
		return out
	if str(season.save.meta.get("uefa", "off")) != "on":
		return out
	var competitions := _published_ids()
	if competitions.is_empty():
		return out
	var entries: Dictionary = {}
	var carried: Array = []
	for iso in _associations(competitions):
		var league := _league_of(competitions, iso)
		var places := _places(played_index, league)
		if places.is_empty():
			carried.append(iso)
			continue
		var picks := _fill(iso, competitions, places, cups)
		if picks.is_empty():
			continue
		_write(iso, picks)
		for pick in picks:
			var cid := str((pick as Dictionary).get("comp", ""))
			var rows: Dictionary = entries.get(cid, {})
			rows[str(pick["club"])] = {"round": str(pick["round"]),
				"source": str(pick["source"]), "kind": str(pick["kind"]),
				"association": iso}
			entries[cid] = rows
	out["ok"] = true
	out["carried"] = carried
	out["entries"] = entries
	season.save.put_meta(META, JSON.stringify({"season": played_index,
		"carried": carried, "entries": entries}))
	season.save.reload()
	return out


static func reading(save: LeagueSave, competition_id: String) -> Dictionary:
	var parsed: Variant = {} if save == null else JSON.parse_string(str(save.meta.get(META, "{}")))
	if not (parsed is Dictionary):
		return {}
	var rows: Variant = (parsed as Dictionary).get("entries", {})
	if not (rows is Dictionary):
		return {}
	var comp: Variant = (rows as Dictionary).get(competition_id, {})
	return comp if comp is Dictionary else {}


static func carried(save: LeagueSave) -> Array:
	var parsed: Variant = {} if save == null else JSON.parse_string(str(save.meta.get(META, "{}")))
	if not (parsed is Dictionary):
		return []
	var list: Variant = (parsed as Dictionary).get("carried", [])
	return list if list is Array else []


static func summary(save: LeagueSave, competition_id: String) -> String:
	if save == null:
		return "SEASON ONE ENTRY LIST"
	var rows := reading(save, competition_id)
	if rows.is_empty():
		return "SEASON ONE ENTRY LIST"
	var places := 0
	var cups := 0
	for key in rows:
		var row: Dictionary = rows[key]
		if str(row.get("kind", "")) == "cup":
			cups += 1
		else:
			places += 1
	var carried_count := 0
	var moving: Array = carried(save)
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club';", [competition_id]):
		if moving.has(LeagueUefa.association_of(str(row["member_id"]))):
			carried_count += 1
	var parts: Array = []
	if places > 0:
		parts.append("%d FROM PLACES" % places)
	if cups > 0:
		parts.append("%d CUP WINNER%s" % [cups, "" if cups == 1 else "S"])
	if carried_count > 0:
		parts.append("%d CARRIED OVER" % carried_count)
	return " · ".join(PackedStringArray(parts))


static func _published_ids() -> Array:
	var out: Array = []
	for cid in LeagueUefa.IDS:
		if published(str(cid)):
			out.append(str(cid))
	return out


static func _associations(competitions: Array) -> Array:
	var out: Array = []
	for cid in competitions:
		var access: Variant = LeagueUefa.rules(str(cid)).get("access", {})
		if not (access is Dictionary):
			continue
		for iso in (access as Dictionary).keys():
			if not out.has(str(iso)):
				out.append(str(iso))
	return out


static func _league_of(competitions: Array, iso: String) -> String:
	for cid in competitions:
		var leagues: Variant = LeagueUefa.rules(str(cid)).get("leagues", {})
		if leagues is Dictionary and (leagues as Dictionary).has(iso):
			return str((leagues as Dictionary)[iso])
	return ""


static func _places(played_index: int, league: String) -> Array:
	var out: Array = []
	if league == "":
		return out
	for row in SeasonArchive.table(played_index, league):
		out.append(str(row["club_id"]))
	return out


static func _access(competition_id: String, iso: String) -> Dictionary:
	var access: Variant = LeagueUefa.rules(competition_id).get("access", {})
	if not (access is Dictionary):
		return {}
	var rows: Variant = (access as Dictionary).get(iso, {})
	return rows if rows is Dictionary else {}


static func _fill(iso: String, competitions: Array, places: Array, cups: Dictionary) -> Array:
	var picks: Array = []
	var taken := {}
	var cursor := 0
	var league := str(LEAGUE_NAMES.get(iso, iso))
	for cid in competitions:
		var rounds := _access(str(cid), iso)
		for round_id in rounds.keys():
			for slot in rounds[round_id]:
				var cell := (slot as Array)
				var kind := str(cell[0])
				var club := ""
				var source := ""
				var counted := "place"
				if kind == "cup":
					var cup := str(cell[1])
					var name := str(CUP_NAMES.get(cup, cup))
					var winner := str(cups.get(cup, ""))
					if winner != "" and not taken.has(winner):
						club = winner
						source = name + " WINNER"
						counted = "cup"
					else:
						source = name + " OFF" if winner == "" else name + " WINNER IN"
						counted = "fallback"
				if club == "":
					while cursor < places.size() and taken.has(str(places[cursor])):
						cursor += 1
					if cursor >= places.size():
						break
					club = str(places[cursor])
					cursor += 1
					var place := "%s %s" % [league, ordinal(cursor)]
					source = place if source == "" else source + " · " + place
				if taken.has(club):
					continue
				taken[club] = true
				picks.append({"comp": str(cid), "round": str(round_id),
					"club": club, "source": source, "kind": counted})
	return picks


static func entrants(save: LeagueSave, competition_id: String) -> Array:
	var notes := reading(save, competition_id)
	var moving: Array = carried(save)
	var rounds := LeagueUefa.round_ids(competition_id)
	rounds.reverse()
	var clubs: Array = []
	for rid in rounds:
		clubs.append_array(LeagueUefa.entrants(competition_id, str(rid)))
	var known := LeagueUefaBands.ensure_bands(save, competition_id, clubs)
	var out: Array = []
	for rid in rounds:
		var round_id := str(rid)
		for club_id in LeagueUefa.entrants(competition_id, round_id):
			var note: Dictionary = notes.get(club_id, {})
			var iso := LeagueUefa.association_of(club_id)
			var source := str(note.get("source", ""))
			if source == "":
				if not notes.is_empty() and moving.has(iso):
					source = "CARRIED OVER"
				elif not notes.is_empty():
					source = "STUB SLOT"
				else:
					source = "SEASON ONE LIST"
			out.append({"club": club_id, "name": LeagueUefa.club_name(club_id),
				"association": iso, "round": round_id,
				"badge": LeagueEurope.badge(round_id),
				"source": source, "kind": str(note.get("kind", "")),
				"band": LeagueUefaBands.band(known, club_id)})
	return out


static func ordinal(place: int) -> String:
	match place:
		1:
			return "1ST"
		2:
			return "2ND"
		3:
			return "3RD"
	return "%dTH" % place


static func _write(iso: String, picks: Array) -> void:
	var drop: Array = []
	for row in PLDatabase.rows(
			"SELECT competition_id, member_id FROM competition_member WHERE member_kind = 'club';"):
		var cid := str(row["competition_id"])
		if not LeagueUefa.is_continental(cid):
			continue
		if LeagueUefa.association_of(str(row["member_id"])) == iso:
			drop.append([cid, str(row["member_id"])])
	for pair in drop:
		PLDatabase.execute(
			"DELETE FROM competition_member WHERE competition_id = ? AND member_kind = 'club' "
			+ "AND member_id = ?;", [str((pair as Array)[0]), str((pair as Array)[1])])
	for pick in picks:
		PLDatabase.execute(
			"INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
			+ "VALUES (?, 'club', ?, ?);",
			[str(pick["comp"]), str(pick["club"]), str(pick["round"])])
