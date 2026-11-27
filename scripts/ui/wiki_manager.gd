class_name WikiManager
extends RefCounted


const CHARACTER_LABELS := [
	["reactive", "REACTIVE"], ["stubborn", "STUBBORN"], ["risk", "RISK"],
	["patience", "PATIENCE"], ["sub_style", "SUB STYLE"],
]

const LEVER_LABELS := {
	"mentality": "MENTALITY", "press": "PRESS", "formation": "FORMATION",
	"width": "WIDTH", "tempo": "TEMPO", "line": "LINE",
	"set_piece": "SET PIECES", "time_wasting": "TIME-WASTING",
}


static func page(club_id: String) -> Dictionary:
	var club := WikiModel.repo().club(club_id)
	if club.is_empty():
		return WikiLeague.page()
	var prof := ManagerData.profile(club_id)
	var board := Tactics.from_team(club, prof)
	var out := {
		"page": WikiModel.MANAGER,
		"id": club_id,
		"title": str(prof.get("name", "The manager")).to_upper(),
		"eyebrow": str(club.get("abbr", club_id)),
		"subtitle": "%s  ·  %s  ·  %s" % [
			str(club.get("name", "")).to_upper(), str(club.get("stadium", "")).to_upper(),
			str(club.get("city", "")).to_upper()],
		"accent": club.get("color", Color.WHITE),
		"blocks": [],
	}
	out["blocks"].append(WikiCompetitions.link(str(club.get("competition", ""))))
	out["blocks"].append({"k": "kv", "items": [
		["FORMATION", board.formation, true],
		["MENTALITY", mentality(board), true],
	]})
	if ManagerData.has_persona(club_id):
		out["blocks"].append({"k": "section", "text": "TEMPERAMENT"})
		var bars: Array = []
		for pair in CHARACTER_LABELS:
			bars.append([str(pair[1]), float(prof.get(pair[0], 0.5))])
		out["blocks"].append({"k": "bars", "items": bars})
		out["blocks"].append({"k": "note", "text": str(prof.get("trait", "")).to_upper()})
		out["blocks"].append({"k": "section", "text": "PREFERRED LEVERS"})
		out["blocks"].append({"k": "note", "text": lever_line(prof.get("levers", []))})
	else:
		out["blocks"].append({"k": "note", "text": "NO TEMPERAMENT RECORDED  ·  THIS CLUB PLAYS THE LEAGUE'S DEFAULT"})
	out["blocks"].append({"k": "chips", "items": [{
		"text": str(club.get("name", "")).to_upper(),
		"target": {"page": WikiModel.TEAM, "id": club_id},
		"accent": WikiModel.hex(club.get("color", Color.WHITE)),
	}]})
	return out


static func mentality(board: Tactics) -> String:
	return str(board.mentality).replace("_", " ").to_upper()


static func lever_line(levers: Array) -> String:
	var out: Array = []
	for lever in levers:
		var key := str(lever)
		out.append(str(LEVER_LABELS.get(key, key.replace("_", " ").to_upper())))
	return "  ·  ".join(PackedStringArray(out))