class_name YouthIntake
extends RefCounted


const NAMES_PATH := "res://data/youth_names.json"
const ROLES := ["GK", "RB", "RCB", "LCB", "LB", "RDM", "LDM", "RW", "CAM", "LW", "ST"]
const ROLE_POOL := ["GK", "RB", "RCB", "LCB", "LB", "RDM", "LDM", "RW", "CAM", "LW", "ST",
	"RCB", "LCB", "RDM", "LDM", "CAM", "RW", "LW", "ST", "ST"]

static var _names: Dictionary = {}


static func names() -> Dictionary:
	if not _names.is_empty():
		return _names
	var text := FileAccess.get_file_as_string(NAMES_PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	_names = parsed if parsed is Dictionary else {}
	return _names


static func apply(save: LeagueSave, season_index: int, date: String) -> Dictionary:
	if save == null or not save.ensure_open():
		return {"ok": false, "reason": "no_save", "clubs": 0, "players": 0}
	if date == "":
		date = save.current_date()
	var seed := int(str(save.meta.get("seed", "0")))
	var clubs := 0
	var players := 0
	var by_club := {}
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for row in PLDatabase.rows("SELECT * FROM club ORDER BY id;"):
		var club: Dictionary = row
		var cid := str(club.get("competition_id", ""))
		if not save.actives.has(cid) or int(club.get("stub", 0)) == 1:
			continue
		var club_id := str(club["id"])
		var count := intake_count(club_id, seed, season_index)
		var made := _club(club, count, seed, season_index, date)
		if made > 0:
			clubs += 1
			players += made
			by_club[club_id] = made
	PLDatabase.transaction("COMMIT;")
	MarketFinance.invalidate()
	return {"ok": true, "clubs": clubs, "players": players, "by_club": by_club, "date": date}


static func intake_count(club_id: String, seed: int, season_index: int) -> int:
	var weight := clampf(float(MarketFinance.reputation(club_id)) / 100.0, 0.0, 1.0)
	var base := 2 + int(round(weight * 6.0))
	var jitter := (MarketSeed.mix(seed, club_id, season_index * 13 + 3) % 3) - 1
	return clampi(base + jitter, 2, 8)


static func tier(club_id: String) -> Array:
	var rep := MarketFinance.reputation(club_id)
	if rep >= 75:
		return [64, 80]
	if rep >= 50:
		return [56, 72]
	if rep >= 25:
		return [48, 64]
	return [42, 58]


static func _club(club: Dictionary, count: int, seed: int, season_index: int,
		date: String) -> int:
	var club_id := str(club["id"])
	var competition_id := str(club.get("competition_id", ""))
	var nationality := _nationality(club)
	var pool: Dictionary = names().get(nationality, names().get("Default", {}))
	var firsts: Array = pool.get("first", ["Alex"])
	var lasts: Array = pool.get("last", ["Novak"])
	var tier_band := tier(club_id)
	var ord_row := PLDatabase.row("SELECT COALESCE(MAX(ord), -1) AS n FROM player WHERE club_id = ?;",
		[club_id])
	var ord := int(ord_row.get("n", -1))
	var end := FixtureCalendar.add_days(FixtureCalendar.add_years(date, 3), -1)
	var step := maxi(MarketRules.count("wage", "round_to", 10), 1)
	var made := 0
	for n in range(count):
		var id := "Y%d-%s-%02d" % [season_index, club_id, n + 1]
		if not PLDatabase.row("SELECT id FROM player WHERE id = ?;", [id]).is_empty():
			continue
		var salt := season_index * 101 + n
		var age := 16 + MarketSeed.mix(seed, id, salt) % 3
		var ovr := int(tier_band[0]) + MarketSeed.mix(seed, id, salt + 1) \
			% (int(tier_band[1]) - int(tier_band[0]) + 1)
		var role: String = ROLE_POOL[MarketSeed.mix(seed, id, salt + 2) % ROLE_POOL.size()]
		var first: String = str(firsts[MarketSeed.mix(seed, id, salt + 3) % firsts.size()])
		var last: String = str(lasts[MarketSeed.mix(seed, id, salt + 4) % lasts.size()])
		var name := "%s %s" % [first.substr(0, 1) + ".", last]
		var number := _number(club_id)
		var height := 168 + MarketSeed.mix(seed, id, salt + 5) % 28
		var attrs := _attributes(ovr, role, seed, id, salt)
		var dob := _dob(date, age, seed, id, salt)
		ord += 1
		if not PLDatabase.execute(
				"INSERT INTO player (id, club_id, name, number, role, pos, ovr, pac, sho, pas, "
				+ "dri, def, phy, height, gk_div, gk_han, gk_kic, gk_ref, gk_spd, squad, ord, "
				+ "espn_id, age, nationality, date_of_birth, subs, extras, ratings_matched, "
				+ "homegrown_club_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, "
				+ "?, ?, 'bench', ?, '', ?, ?, ?, '{}', ?, 0, ?);",
				[id, club_id, name, number, role, role, ovr, attrs["pac"], attrs["sho"],
				 attrs["pas"], attrs["dri"], attrs["def"], attrs["phy"], height,
				 attrs["gk"][0], attrs["gk"][1], attrs["gk"][2], attrs["gk"][3],
				 attrs["gk"][4], ord, age, nationality, dob, JSON.stringify({"potential": ovr}),
				 club_id]):
			continue
		var wage := maxi(step, int(round(float(ovr) * 12.0 / float(step))) * step)
		PLDatabase.execute(
			"INSERT OR REPLACE INTO player_contract (player_id, club_id, season_index, start_date, "
			+ "end_date, wage, signing_bonus, agent_fee, release_clause, option_years, status, "
			+ "deal_id, declined) VALUES (?, ?, ?, ?, ?, ?, 0, 0, ?, 0, 'active', '', 0);",
			[id, club_id, season_index, date, end, wage, wage * 52 * 2])
		PLDatabase.execute(
			"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
			+ "state, reason, deal_id, season_index, u21_exempt) "
			+ "VALUES (?, ?, ?, 'youth', 'registered', '', '', ?, 1);",
			[id, competition_id, club_id, season_index])
		made += 1
	return made


static func _nationality(club: Dictionary) -> String:
	var code := MarketWindows.country_of_club(club)
	var by_code := {
		"ENG": "England", "WAL": "England", "SCO": "England", "NIR": "England",
		"ESP": "Spain", "GER": "Germany", "ITA": "Italy", "FRA": "France",
		"NED": "Netherlands", "POR": "Portugal", "BRA": "Brazil",
	}
	if by_code.has(code):
		return str(by_code[code])
	var country := str(club.get("country", ""))
	if by_code.has(country):
		return str(by_code[country])
	return "Default"


static func _number(club_id: String) -> int:
	var taken := {}
	for row in PLDatabase.rows("SELECT number FROM player WHERE club_id = ?;", [club_id]):
		taken[int(row.get("number", 0))] = true
	for number in range(1, 100):
		if not taken.has(number):
			return number
	return 100


static func _dob(date: String, age: int, seed: int, id: String, salt: int) -> String:
	var year := int(date.substr(0, 4)) - age
	var month := 1 + MarketSeed.mix(seed, id, salt + 6) % 12
	var day := 1 + MarketSeed.mix(seed, id, salt + 7) % 28
	return "%04d-%02d-%02d" % [year, month, day]


static func _attributes(ovr: int, role: String, seed: int, id: String, salt: int) -> Dictionary:
	var out := {"pac": 50, "sho": 50, "pas": 50, "dri": 50, "def": 50, "phy": 50,
		"gk": [ovr, ovr, ovr, ovr, ovr]}
	if role == "GK":
		out["pac"] = clampi(ovr - 20 + _jitter(seed, id, salt, 10), 1, 99)
		out["sho"] = clampi(20 + _jitter(seed, id, salt, 11), 1, 99)
		out["pas"] = clampi(ovr - 5 + _jitter(seed, id, salt, 12), 1, 99)
		out["dri"] = clampi(ovr - 10 + _jitter(seed, id, salt, 13), 1, 99)
		out["def"] = clampi(30 + _jitter(seed, id, salt, 14), 1, 99)
		out["phy"] = clampi(ovr - 5 + _jitter(seed, id, salt, 15), 1, 99)
		out["gk"] = [
			clampi(ovr + _jitter(seed, id, salt, 16), 1, 99),
			clampi(ovr + _jitter(seed, id, salt, 17), 1, 99),
			clampi(ovr + _jitter(seed, id, salt, 18), 1, 99),
			clampi(ovr + _jitter(seed, id, salt, 19), 1, 99),
			clampi(ovr - 20 + _jitter(seed, id, salt, 20), 1, 99),
		]
		return out
	var profile: Dictionary = {
		"pac": 0, "sho": 0, "pas": 0, "dri": 0, "def": 0, "phy": 0,
	}
	match role:
		"RB", "LB":
			profile = {"pac": 8, "sho": -12, "pas": 0, "dri": 2, "def": 4, "phy": 0}
		"RCB", "LCB":
			profile = {"pac": -2, "sho": -18, "pas": -4, "dri": -8, "def": 12, "phy": 8}
		"RDM", "LDM":
			profile = {"pac": -2, "sho": -8, "pas": 6, "dri": 2, "def": 8, "phy": 6}
		"CAM":
			profile = {"pac": 4, "sho": 4, "pas": 8, "dri": 10, "def": -12, "phy": -4}
		"RW", "LW":
			profile = {"pac": 10, "sho": 4, "pas": 2, "dri": 10, "def": -12, "phy": -4}
		"ST":
			profile = {"pac": 6, "sho": 12, "pas": -4, "dri": 4, "def": -16, "phy": 6}
	var key := 30
	for stat in ["pac", "sho", "pas", "dri", "def", "phy"]:
		out[stat] = clampi(ovr + int(profile.get(stat, 0)) + _jitter(seed, id, salt, key), 1, 99)
		key += 1
	return out


static func _jitter(seed: int, id: String, salt: int, key: int) -> int:
	return (MarketSeed.mix(seed, id, salt + key) % 17) - 8
