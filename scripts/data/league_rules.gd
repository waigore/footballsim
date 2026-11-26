class_name LeagueRules
extends RefCounted

## League regulations, one row per active competition: points, European and
## relegation places, the calendar window and the advance policy.
##
## The templates are the shipped competitions' own regulations (cups omitted):
## the Premier League's and La Liga's 20-club, 38-matchday shape with 1–4 to the
## Champions League, 5th to the Europa League, 6th to the Conference League and
## three relegated. A save copies each active competition's template into its
## own row at creation, so a later seed refresh or a regulation change can never
## rewrite a season already in progress.
##
## `advance_mode` and `calendar_mode` belong to the save, not to one league: the
## clock is shared, so the two rows always carry the same pair. They live here so
## a save written before multi-league keeps reading its own choice.

const TEMPLATES := {
	"PL": {
		"win_points": 3, "draw_points": 1, "relegation_places": 3,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38,
		"season_start": "2026-08-15", "season_end": "2027-05-23",
		"weekend_bias": 0.85, "midweek_matchdays": 5,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
	},
	"LL": {
		# La Liga runs the same 20-club shape; Spain's own band counts are the
		# same 4 / 1 / 1 and three relegated. Spain plays more weekend rounds, so
		# four rounds move midweek rather than England's five.
		"win_points": 3, "draw_points": 1, "relegation_places": 3,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 38,
		"season_start": "2026-08-15", "season_end": "2027-05-23",
		"weekend_bias": 0.88, "midweek_matchdays": 4,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
	},
	"BL": {
		# The Bundesliga's 18-club, 34-matchday shape. Without a domestic cup
		# in the save, 1-4 go to the Champions League, 5th to the Europa League
		# and 6th to the Conference League; 17th and 18th go down directly and
		# 16th plays the Relegation (the graph itself lands with #240).
		"win_points": 3, "draw_points": 1, "clubs": 18,
		"relegation_places": 2, "relegation_playoff_places": 1,
		"ucl_places": 4, "uel_places": 1, "uecl_places": 1, "matchdays": 34,
		"season_start": "2026-08-28", "season_end": "2027-05-22",
		"weekend_bias": 0.88, "midweek_matchdays": 4,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
	},
	"BL2": {
		# 18 clubs, 34 matchdays. 1st and 2nd go up and 3rd plays the Relegation;
		# 17th and 18th go down. No European bands: the 2.BL podium reads
		# promotion or RELEGATED only (the graph itself lands with #240).
		"win_points": 3, "draw_points": 1, "clubs": 18,
		"promotion_places": 2, "promotion_playoff_places": 1,
		"relegation_places": 2, "relegation_playoff_places": 1,
		"ucl_places": 0, "uel_places": 0, "uecl_places": 0, "matchdays": 34,
		"season_start": "2026-08-07", "season_end": "2027-05-23",
		"weekend_bias": 0.88, "midweek_matchdays": 4,
		"advance_mode": "fixture_days", "calendar_mode": "generated",
	},
}

## The v1 Premier League template, kept as the default for a caller that names
## no competition (single-league tests and an old save's fallback).
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
	+ "advance_mode TEXT NOT NULL, calendar_mode TEXT NOT NULL);"
)

const UPSERT_SQL := (
	"INSERT INTO league_rules (competition_id, win_points, draw_points, relegation_places, "
	+ "ucl_places, uel_places, uecl_places, matchdays, season_start, season_end, weekend_bias, "
	+ "midweek_matchdays, advance_mode, calendar_mode) "
	+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
	+ "ON CONFLICT(competition_id) DO UPDATE SET win_points = excluded.win_points, "
	+ "draw_points = excluded.draw_points, relegation_places = excluded.relegation_places, "
	+ "ucl_places = excluded.ucl_places, uel_places = excluded.uel_places, "
	+ "uecl_places = excluded.uecl_places, matchdays = excluded.matchdays, "
	+ "season_start = excluded.season_start, season_end = excluded.season_end, "
	+ "weekend_bias = excluded.weekend_bias, midweek_matchdays = excluded.midweek_matchdays, "
	+ "advance_mode = excluded.advance_mode, calendar_mode = excluded.calendar_mode;"
)

const COLUMNS := [
	"win_points", "draw_points", "relegation_places", "ucl_places", "uel_places",
	"uecl_places", "matchdays", "season_start", "season_end", "weekend_bias",
	"midweek_matchdays", "advance_mode", "calendar_mode",
]

## The template with both setup choices filled in.
static func defaults(calendar_mode: String = "generated", advance_mode: String = "fixture_days",
		competition_id: String = "PL") -> Dictionary:
	var out: Dictionary = template(competition_id).duplicate(true)
	out["calendar_mode"] = calendar_mode if CALENDAR_MODES.has(calendar_mode) else "generated"
	out["advance_mode"] = advance_mode if ADVANCE_MODES.has(advance_mode) else "fixture_days"
	return out

## One competition's shipped template, without the setup choices applied.
static func template(competition_id: String) -> Dictionary:
	var row: Dictionary = TEMPLATES.get(competition_id, DEFAULTS)
	return row.duplicate(true)

## The template a competition row in the seed carries when it ships its own
## regulations; the compiled template is the fallback.
static func template_from(competition_id: String, stored: Dictionary) -> Dictionary:
	var out := template(competition_id)
	for key in stored.keys():
		out[key] = stored[key]
	return out

## Read one competition's regulations from the bound save. With no competition
## id the save's primary row answers, which is what a single-league caller (and
## an old save) expects.
static func read(competition_id: String = "") -> Dictionary:
	var row := {}
	if competition_id == "":
		row = PLDatabase.row("SELECT * FROM league_rules ORDER BY rowid LIMIT 1;")
	else:
		row = PLDatabase.row("SELECT * FROM league_rules WHERE competition_id = ?;", [competition_id])
	if row.is_empty():
		return defaults("generated", "fixture_days", competition_id if competition_id != "" else "PL")
	return normalize(row)

## Every competition's regulations, keyed by competition id.
static func read_all() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("SELECT * FROM league_rules ORDER BY rowid;"):
		var cid := str(row.get("competition_id", "PL"))
		out[cid] = normalize(row)
	return out

## Coerce a row (or a partial dictionary) into the typed rules dictionary.
static func normalize(raw: Dictionary) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	for key in ["win_points", "draw_points", "relegation_places", "ucl_places",
			"uel_places", "uecl_places", "matchdays", "midweek_matchdays"]:
		if raw.has(key):
			out[key] = int(raw[key])
	for key in ["season_start", "season_end", "advance_mode", "calendar_mode"]:
		if raw.has(key):
			out[key] = str(raw[key])
	if raw.has("weekend_bias"):
		out["weekend_bias"] = float(raw["weekend_bias"])
	return out

## Copy one competition's regulations into the bound save.
static func write(competition_id: String, rules: Dictionary) -> bool:
	var r := normalize(rules)
	var bindings: Array = [competition_id]
	for key in COLUMNS:
		bindings.append(r[key])
	return PLDatabase.execute(UPSERT_SQL, bindings)

## Lay the per-competition rules table onto the bound file and lift a save that
## shipped before multi-league: its single `league_rules` row has an `id`
## column and no `competition_id`. The old row is copied under the save's one
## competition, so a season in progress keeps its own places.
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

static func _columns(table: String) -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
		out[str(row["name"])] = true
	return out

## Points for one result from the saved table (win / draw values are not
## hard-coded: a save can carry different regulations).
static func points(goals_for: int, goals_against: int, rules: Dictionary) -> int:
	if goals_for > goals_against:
		return int(rules.get("win_points", 3))
	if goals_for == goals_against:
		return int(rules.get("draw_points", 1))
	return 0

## Which table band a position sits in: "ucl", "uel", "uecl", "relegation" or "".
static func zone(position: int, rules: Dictionary) -> String:
	var ucl := int(rules.get("ucl_places", 4))
	var uel := int(rules.get("uel_places", 1))
	var uecl := int(rules.get("uecl_places", 1))
	var down := int(rules.get("relegation_places", 3))
	var size := int(rules.get("clubs", 20))
	if position <= ucl:
		return "ucl"
	if position <= ucl + uel:
		return "uel"
	if position <= ucl + uel + uecl:
		return "uecl"
	if position > size - down:
		return "relegation"
	return ""

static func zone_label(band: String) -> String:
	if band == "ucl":
		return "UCL"
	if band == "uel":
		return "UEL"
	if band == "uecl":
		return "UECL"
	if band == "relegation":
		return "REL"
	return ""

## Places that matter at the end of the season, read back from the save.
static func places(rules: Dictionary) -> Dictionary:
	var ucl := int(rules.get("ucl_places", 4))
	var uel := int(rules.get("uel_places", 1))
	var uecl := int(rules.get("uecl_places", 1))
	return {
		"ucl": ucl,
		"uel": uel,
		"uecl": uecl,
		"relegation": int(rules.get("relegation_places", 3)),
		"europe": ucl + uel + uecl,
	}
