class_name LeagueCup
extends RefCounted


const COUNTRY_LEAGUES := {
	"England": ["PL", "CH", "L1", "L2", "NL"],
	"Spain": ["LL"],
	"Germany": ["BL", "BL2"],
	"Italy": ["SA", "SB"],
}

const LEAGUE_TIER := {
	"PL": 1, "CH": 2, "L1": 3, "L2": 4, "NL": 5, "LL": 1, "BL": 1, "BL2": 2,
	"SA": 1, "SB": 2,
}


static func rules(competition_id: String) -> Dictionary:
	var row := PLRepository.shared().competition(competition_id)
	var data: Variant = row.get("rules", {})
	return data if data is Dictionary else {}


static func kind(competition_id: String) -> String:
	return str(rules(competition_id).get("kind", "league"))


static func is_cup(competition_id: String) -> bool:
	var cup_kind := kind(competition_id)
	return cup_kind == "cup" or cup_kind == "supercup"


static func is_cup_fixture(fixture: Dictionary) -> bool:
	return is_cup(str(fixture.get("competition_id", ""))) \
		and str(fixture.get("stage", "")) != ""


static func active_ids(save: LeagueSave) -> Array:
	var out: Array = []
	if save == null or str(save.meta.get("cups", "off")) != "on":
		return out
	var off := str(save.meta.get("cups_off", ""))
	for row in PLRepository.shared().cups():
		var cid := str(row.get("id", ""))
		var country := str(row.get("country", ""))
		if off != "" and ("," + off + ",").find("," + country + ",") >= 0:
			continue
		for league_id in COUNTRY_LEAGUES.get(country, []):
			if save.actives.has(league_id):
				out.append(cid)
				break
	return out


static func countries() -> Array:
	var out: Array = []
	for row in PLRepository.shared().cups():
		var country := str(row.get("country", ""))
		if country == "" or out.has(country):
			continue
		if not LeagueTiers.countries().has(country):
			continue
		out.append(country)
	return out


static func rounds(competition_id: String) -> Array:
	var list: Variant = rules(competition_id).get("rounds", [])
	return list if list is Array else []


static func round_rule(competition_id: String, round_id: String) -> Dictionary:
	for row in rounds(competition_id):
		if str((row as Dictionary).get("id", "")) == round_id:
			return row
	return {}


static func round_index(competition_id: String, round_id: String) -> int:
	var all := rounds(competition_id)
	for i in range(all.size()):
		if str((all[i] as Dictionary).get("id", "")) == round_id:
			return i
	return -1


static func next_round(competition_id: String, round_id: String) -> String:
	var index := round_index(competition_id, round_id)
	var all := rounds(competition_id)
	if index < 0 or index + 1 >= all.size():
		return ""
	return str((all[index + 1] as Dictionary).get("id", ""))


static func entrants(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' AND role = ? ORDER BY member_id;",
			[competition_id, round_id]):
		out.append(str(row["member_id"]))
	return out


static func tier_of(club_id: String) -> int:
	var club := PLRepository.shared().club(club_id)
	var own := str(club.get("competition_id", ""))
	if LEAGUE_TIER.has(own):
		return int(LEAGUE_TIER[own])
	return int(club.get("tier", 9))


static func region_of(club_id: String) -> String:
	var club := PLRepository.shared().club(club_id)
	var region := str(club.get("region", ""))
	return region if region != "" else "south"


static func name_of(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("name", club_id))


static func abbr_of(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("abbr", club_id))


static func host_order(competition_id: String, round_id: String, a: String, b: String) -> Array:
	var host := str(round_rule(competition_id, round_id).get("host", "draw"))
	if host == "lower":
		var tier_a := tier_of(a)
		var tier_b := tier_of(b)
		if tier_a != tier_b:
			return [b, a] if tier_a < tier_b else [a, b]
	return [a, b]


static func stage_of(competition_id: String) -> String:
	var open := ""
	for row in rounds(competition_id):
		var rid := str((row as Dictionary).get("id", ""))
		if not has_round(competition_id, rid):
			return open if open != "" else rid
		if not round_complete(competition_id, rid):
			return rid
		open = rid
	return open


static func has_round(competition_id: String, round_id: String) -> bool:
	var row := PLDatabase.row(
		"SELECT 1 AS n FROM cup_round WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	return not row.is_empty()


static func round_complete(competition_id: String, round_id: String) -> bool:
	var total := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	var done := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ? "
		+ "AND winner_club_id <> '';",
		[competition_id, round_id])
	return int(total.get("n", 0)) > 0 and int(done.get("n", 0)) == int(total.get("n", 0))
