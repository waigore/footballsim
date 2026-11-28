class_name LeagueRules
extends RefCounted


const TEMPLATES := {
	"PL": {
		"win_points": 3, "draw_points": 1, "relegation_places": 3,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38, "clubs": 20,
		"promotion_places": 0, "promotion_playoff_places": 0, "relegation_playoff_places": 0,
		"promotion_skip_gap": 0, "playout_places": 0,
		"season_start": "2026-08-15", "season_end": "2027-05-23",
		"weekend_bias": 0.85, "midweek_matchdays": 5,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "",
	},
	"LL": {


		"win_points": 3, "draw_points": 1, "relegation_places": 3,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38, "clubs": 20,
		"promotion_places": 0, "promotion_playoff_places": 0, "relegation_playoff_places": 0,
		"promotion_skip_gap": 0, "playout_places": 0,
		"season_start": "2026-08-15", "season_end": "2027-05-23",
		"weekend_bias": 0.88, "midweek_matchdays": 4,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "",
	},
	"LL2": {


		"win_points": 3, "draw_points": 1, "clubs": 22,
		"promotion_places": 2, "promotion_playoff_places": 4,
		"relegation_places": 4, "relegation_playoff_places": 0, "playout_places": 0,
		"promotion_skip_gap": 0,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0, "matchdays": 42,
		"season_start": "2026-08-14", "season_end": "2027-06-06",
		"weekend_bias": 0.85, "midweek_matchdays": 6,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "segunda_four_two_leg",
	},
	"BL": {


		"win_points": 3, "draw_points": 1, "clubs": 18,
		"relegation_places": 2, "relegation_playoff_places": 1,
		"promotion_skip_gap": 0, "playout_places": 0,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 34,
		"season_start": "2026-08-28", "season_end": "2027-05-22",
		"weekend_bias": 0.88, "midweek_matchdays": 4,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "",
	},
	"BL2": {


		"win_points": 3, "draw_points": 1, "clubs": 18,
		"promotion_places": 2, "promotion_playoff_places": 1,
		"relegation_places": 2, "relegation_playoff_places": 1,
		"promotion_skip_gap": 0, "playout_places": 0,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0, "matchdays": 34,
		"season_start": "2026-08-07", "season_end": "2027-05-23",
		"weekend_bias": 0.88, "midweek_matchdays": 4,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "",
	},
	"SA": {


		"win_points": 3, "draw_points": 1, "clubs": 20,
		"relegation_places": 3, "relegation_playoff_places": 0, "playout_places": 0,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38,
		"promotion_places": 0, "promotion_playoff_places": 0, "promotion_skip_gap": 0,
		"season_start": "2026-08-22", "season_end": "2027-05-23",
		"weekend_bias": 0.88, "midweek_matchdays": 5,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "",
	},
	"SB": {


		"win_points": 3, "draw_points": 1, "clubs": 20,
		"promotion_places": 2, "promotion_playoff_places": 6, "promotion_skip_gap": 14,
		"relegation_places": 3, "relegation_playoff_places": 0, "playout_places": 2,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0, "matchdays": 38,
		"season_start": "2026-08-22", "season_end": "2027-05-09",
		"weekend_bias": 0.85, "midweek_matchdays": 6,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "serie_b_six",
	},


	"CH": {

		"win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
		"promotion_places": 2, "promotion_playoff_places": 6,
		"relegation_places": 3, "relegation_playoff_places": 0,
		"promotion_skip_gap": 0, "playout_places": 0,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0,
		"season_start": "2026-08-07", "season_end": "2027-05-10",
		"weekend_bias": 0.85, "midweek_matchdays": 8,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "six_two_leg",
	},
	"L1": {

		"win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
		"promotion_places": 2, "promotion_playoff_places": 4,
		"relegation_places": 4, "relegation_playoff_places": 0,
		"promotion_skip_gap": 0, "playout_places": 0,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0,
		"season_start": "2026-08-07", "season_end": "2027-05-10",
		"weekend_bias": 0.85, "midweek_matchdays": 8,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "four_two_leg",
	},
	"L2": {

		"win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
		"promotion_places": 3, "promotion_playoff_places": 4,
		"relegation_places": 2, "relegation_playoff_places": 0,
		"promotion_skip_gap": 0, "playout_places": 0,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0,
		"season_start": "2026-08-07", "season_end": "2027-05-10",
		"weekend_bias": 0.85, "midweek_matchdays": 8,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "four_two_leg",
	},
	"NL": {


		"win_points": 3, "draw_points": 1, "clubs": 24, "matchdays": 46,
		"promotion_places": 1, "promotion_playoff_places": 6,
		"relegation_places": 4, "relegation_playoff_places": 0,
		"promotion_skip_gap": 0, "playout_places": 0,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0,
		"season_start": "2026-08-08", "season_end": "2027-05-02",
		"weekend_bias": 0.85, "midweek_matchdays": 8,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
		"playoff_format": "six_one_leg",
	},
}


const DEFAULTS := TEMPLATES["PL"]

const ADVANCE_MODES := ["fixture_days", "every_day"]
const CALENDAR_MODES := ["real", "generated"]

const CREATE_SQL := (
	"CREATE TABLE IF NOT EXISTS league_rules (competition_id TEXT PRIMARY KEY, "
	+ "win_points INTEGER NOT NULL, draw_points INTEGER NOT NULL, "
	+ "relegation_places INTEGER NOT NULL, ucl_places INTEGER NOT NULL, "
	+ "uel_places INTEGER NOT NULL, uecl_places INTEGER NOT NULL, "
	+ "matchdays INTEGER NOT NULL, season_start TEXT NOT NULL, season_end TEXT NOT NULL, "
	+ "weekend_bias REAL NOT NULL, midweek_matchdays INTEGER NOT NULL, "
	+ "advance_mode TEXT NOT NULL, calendar_mode TEXT NOT NULL, "
	+ "clubs INTEGER NOT NULL DEFAULT 20, promotion_places INTEGER NOT NULL DEFAULT 0, "
	+ "promotion_playoff_places INTEGER NOT NULL DEFAULT 0, "
	+ "relegation_playoff_places INTEGER NOT NULL DEFAULT 0, "
	+ "promotion_skip_gap INTEGER NOT NULL DEFAULT 0, "
	+ "playout_places INTEGER NOT NULL DEFAULT 0, "
	+ "playoff_format TEXT NOT NULL DEFAULT '');"
)

const UPSERT_SQL := (
	"INSERT INTO league_rules (competition_id, win_points, draw_points, relegation_places, "
	+ "ucl_places, uel_places, uecl_places, matchdays, season_start, season_end, weekend_bias, "
	+ "midweek_matchdays, advance_mode, calendar_mode, clubs, promotion_places, "
	+ "promotion_playoff_places, relegation_playoff_places, promotion_skip_gap, playout_places, "
	+ "playoff_format) "
	+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
	+ "ON CONFLICT(competition_id) DO UPDATE SET win_points = excluded.win_points, "
	+ "draw_points = excluded.draw_points, relegation_places = excluded.relegation_places, "
	+ "ucl_places = excluded.ucl_places, uel_places = excluded.uel_places, "
	+ "uecl_places = excluded.uecl_places, matchdays = excluded.matchdays, "
	+ "season_start = excluded.season_start, season_end = excluded.season_end, "
	+ "weekend_bias = excluded.weekend_bias, midweek_matchdays = excluded.midweek_matchdays, "
	+ "advance_mode = excluded.advance_mode, calendar_mode = excluded.calendar_mode, "
	+ "clubs = excluded.clubs, promotion_places = excluded.promotion_places, "
	+ "promotion_playoff_places = excluded.promotion_playoff_places, "
	+ "relegation_playoff_places = excluded.relegation_playoff_places, "
	+ "promotion_skip_gap = excluded.promotion_skip_gap, "
	+ "playout_places = excluded.playout_places, "
	+ "playoff_format = excluded.playoff_format;"
)


const LINK_COLUMNS := [
	"clubs", "promotion_places", "promotion_playoff_places", "relegation_playoff_places",
	"promotion_skip_gap", "playout_places",
]


const TEXT_COLUMNS := ["playoff_format"]

const COLUMNS := [
	"win_points", "draw_points", "relegation_places", "ucl_places", "uel_places",
	"uecl_places", "matchdays", "season_start", "season_end", "weekend_bias",
	"midweek_matchdays", "advance_mode", "calendar_mode", "clubs", "promotion_places",
	"promotion_playoff_places", "relegation_playoff_places", "promotion_skip_gap",
	"playout_places", "playoff_format",
]


static func defaults(calendar_mode: String = "generated", advance_mode: String = "fixture_days",
		competition_id: String = "PL") -> Dictionary:
	var out: Dictionary = template(competition_id).duplicate(true)
	out["calendar_mode"] = calendar_mode if CALENDAR_MODES.has(calendar_mode) else "generated"
	out["advance_mode"] = advance_mode if ADVANCE_MODES.has(advance_mode) else "fixture_days"
	return out


static func template(competition_id: String) -> Dictionary:
	var row: Dictionary = TEMPLATES.get(competition_id, DEFAULTS)
	return row.duplicate(true)


static func template_from(competition_id: String, stored: Dictionary) -> Dictionary:
	var out := template(competition_id)
	for key in stored.keys():
		out[key] = stored[key]
	return out


static func read(competition_id: String = "") -> Dictionary:
	var row := {}
	if competition_id == "":
		row = PLDatabase.row("SELECT * FROM league_rules ORDER BY rowid LIMIT 1;")
	else:
		row = PLDatabase.row("SELECT * FROM league_rules WHERE competition_id = ?;", [competition_id])
	if row.is_empty():
		return defaults("generated", "fixture_days", competition_id if competition_id != "" else "PL")
	return normalize(row)


static func read_all() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT * FROM league_rules ORDER BY rowid;"):
		var cid := str(row.get("competition_id", "PL"))
		out[cid] = normalize(row)
	return out


static func normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for key in ["win_points", "draw_points", "relegation_places", "ucl_places",
			"uel_places", "uecl_places", "matchdays", "midweek_matchdays", "clubs",
			"promotion_places", "promotion_playoff_places", "relegation_playoff_places",
			"promotion_skip_gap", "playout_places"]:
		out[key] = int(raw.get(key, out.get(key, 0)))
	for key in ["season_start", "season_end", "advance_mode", "calendar_mode", "playoff_format"]:
		if raw.has(key):
			out[key] = str(raw[key])
	if raw.has("weekend_bias"):
		out["weekend_bias"] = float(raw["weekend_bias"])
	return out


static func write(competition_id: String, rules: Dictionary) -> bool:
	var r := normalize(rules)
	var bindings: Array = [competition_id]
	for key in COLUMNS:
		bindings.append(r[key])
	return PLDatabase.execute(UPSERT_SQL, bindings)


static func migrate(default_competition: String = "") -> void:
	var columns := _columns("league_rules")
	if not columns.is_empty() and not columns.has("competition_id"):
		var owner := default_competition
		if owner == "":
			var meta := PLDatabase.row("SELECT value FROM metadata WHERE key = 'league_name';")
			owner = "LL" if str(meta.get("value", "")).to_lower().begins_with("la liga") else "PL"
		PLDatabase.transaction("BEGIN TRANSACTION;")
		PLDatabase.execute("ALTER TABLE league_rules RENAME TO league_rules_pre_multi;")
		PLDatabase.execute(CREATE_SQL)
		var old := PLDatabase.row("SELECT * FROM league_rules_pre_multi WHERE id = 1;")
		PLDatabase.execute("DROP TABLE league_rules_pre_multi;")
		PLDatabase.transaction("COMMIT;")
		if not old.is_empty():
			write(owner, normalize(old))
		return
	PLDatabase.execute(CREATE_SQL)


	var have := _columns("league_rules")
	for column in LINK_COLUMNS:
		if not have.has(column):
			PLDatabase.execute("ALTER TABLE league_rules ADD COLUMN %s INTEGER NOT NULL DEFAULT 0;"
				% column)


	for column in TEXT_COLUMNS:
		if not have.has(column):
			PLDatabase.execute("ALTER TABLE league_rules ADD COLUMN %s TEXT NOT NULL DEFAULT '';"
				% column)

static func _columns(table: String) -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
		out[str(row["name"])] = true
	return out


static func points(goals_for: int, goals_against: int, rules: Dictionary) -> int:
	if goals_for > goals_against:
		return int(rules.get("win_points", 3))
	if goals_for == goals_against:
		return int(rules.get("draw_points", 1))
	return 0


static func zone(position: int, rules: Dictionary) -> String:
	var ucl := int(rules.get("ucl_places", 4))
	var uel := int(rules.get("uel_places", 1))
	var uecl := int(rules.get("uecl_places", 1))
	var up := int(rules.get("promotion_places", 0))
	var up_playoff := int(rules.get("promotion_playoff_places", 0))
	var down := int(rules.get("relegation_places", 3))
	var playoff := int(rules.get("relegation_playoff_places", 0))
	var playout := int(rules.get("playout_places", 0))
	var size := int(rules.get("clubs", 20))
	if up > 0 and position <= up:
		return "promotion"
	if up > 0 and position <= up + up_playoff:
		return "playoff"
	if position <= ucl:
		return "ucl"
	if position <= ucl + uel:
		return "uel"
	if position <= ucl + uel + uecl:
		return "uecl"
	if position > size - down:
		return "relegation"
	if playout > 0 and position > size - down - playout:
		return "playout"
	if playoff > 0 and position > size - down - playoff:
		return "playoff"
	return ""

static func zone_label(band: String) -> String:
	if band == "ucl":
		return "UCL"
	if band == "uel":
		return "UEL"
	if band == "uecl":
		return "UECL"
	if band == "promotion":
		return "UP"
	if band == "playoff":
		return "PLO"
	if band == "playout":
		return "PLY"
	if band == "relegation":
		return "REL"
	return ""


static func places(rules: Dictionary) -> Dictionary:
	var ucl := int(rules.get("ucl_places", 4))
	var uel := int(rules.get("uel_places", 1))
	var uecl := int(rules.get("uecl_places", 1))
	return {
		"ucl": ucl,
		"uel": uel,
		"uecl": uecl,
		"promotion": int(rules.get("promotion_places", 0)),
		"playoff": int(rules.get("relegation_playoff_places", 0)),
		"playout": int(rules.get("playout_places", 0)),
		"relegation": int(rules.get("relegation_places", 3)),
		"europe": ucl + uel + uecl,
	}
