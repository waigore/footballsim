class_name WikiPlayer
extends RefCounted


static func page(player_id: String) -> Dictionary:
	var p := WikiModel.repo().player(player_id)
	if p.is_empty():
		return WikiLeague.page()
	var club := WikiModel.repo().club(str(p["club_id"]))
	var season: Dictionary = p.get("season", {})
	var career: Dictionary = p.get("career", {})
	var sim: Dictionary = p.get("sim", {})
	var identity := "%s  ·  %s  ·  #%d" % [str(club.get("name", "")).to_upper(), str(p["pos"]), int(p["number"])]
	var extra: Array = []
	if int(p.get("age", 0)) > 0:
		extra.append("%d" % int(p["age"]))
	if str(p.get("nationality", "")) != "":
		extra.append(str(p["nationality"]).to_upper())
	if extra.size() > 0:
		identity += "  ·  " + "  ·  ".join(PackedStringArray(extra))
	var out := {
		"page": WikiModel.PLAYER,
		"id": player_id,
		"title": str(p["name"]).to_upper(),
		"eyebrow": str(club.get("abbr", "")),
		"subtitle": identity,
		"accent": club.get("color", Color.WHITE),
		"blocks": [],
	}
	var summary: Array = [
		["OVERALL", str(int(p["ovr"])), true],
		["POSITION", str(p["pos"]), false],
		["ROLE", str(p["role"]), false],
		["HEIGHT", "%d CM" % int(p["height"]), false],
		["SQUAD", "STARTING XI" if str(p["squad"]) == "starter" else "BENCH", false],
	]
	var absence := WikiAbsence.status_of(str(p["club_id"]), player_id)
	if absence != "":
		summary.append(["STATUS", absence, false])
	out["blocks"].append({"k": "kv", "items": summary})
	out["blocks"].append({"k": "section", "text": "ATTRIBUTES"})
	var bars: Array = []
	if str(p["role"]) == "GK":
		for pair in [["div", "DIVING"], ["han", "HANDLING"], ["kic", "KICKING"], ["ref", "REFLEXES"], ["spd", "SPEED"]]:
			bars.append([str(pair[1]), float(p["gk"].get(pair[0], 30)) / 100.0])
	else:
		for pair in [["pac", "PACE"], ["sho", "SHOOTING"], ["pas", "PASSING"], ["dri", "DRIBBLING"], ["def", "DEFENDING"], ["phy", "PHYSICAL"]]:
			bars.append([str(pair[1]), float(p[pair[0]]) / 100.0])
	out["blocks"].append({"k": "bars", "items": bars})
	var season_label := str(season.get("season_label", ""))
	var season_head := "SEASON"
	if season_label != "":
		season_head += "  ·  " + season_label
	out["blocks"].append({"k": "section", "text": season_head})
	if int(season.get("matches", 0)) > 0:
		out["blocks"].append({
			"k": "kv",
			"items": [
				["APPS", str(int(season["matches"])), true], ["STARTS", str(int(season["starts"])), false],
				["GOALS", count(season, "goals"), true], ["ASSISTS", count(season, "assists"), false],
				["MINUTES", str(int(season["minutes"])), false],
				["CARDS", "%d / %d" % [int(season["yellow"]), int(season["red"])], false],
			],
		})
	else:
		out["blocks"].append({"k": "note", "text": "NO SEASON STATISTICS YET"})
	out["blocks"].append({"k": "section", "text": "CAREER"})
	if int(career.get("matches", 0)) > 0:
		out["blocks"].append({
			"k": "kv",
			"items": [
				["APPS", str(int(career["matches"])), true], ["GOALS", count(career, "goals"), true],
				["ASSISTS", count(career, "assists"), false],
			],
		})
	else:
		out["blocks"].append({"k": "note", "text": "NO CAREER TOTALS YET"})
	var season_open := WikiModel.repo().season_active()
	out["blocks"].append({"k": "section", "text": WikiLedger.heading("IN FOOTBALLSIM")})
	out["blocks"].append(WikiLedger.player_line(sim, season_open))
	out["blocks"].append_array(WikiPlayerLog.blocks(player_id, str(p["club_id"])))
	out["blocks"].append({"k": "chips", "items": [{
		"text": str(club.get("name", "")).to_upper(),
		"target": {"page": WikiModel.TEAM, "id": str(p["club_id"])},
		"accent": WikiModel.hex(club.get("color", Color.WHITE)),
	}]})
	out["blocks"].append(WikiCompetitions.link(str(club.get("competition", ""))))
	return out


static func count(source: Dictionary, key: String) -> String:
	var value := int(source.get(key, -1))
	return "—" if value < 0 else str(value)
