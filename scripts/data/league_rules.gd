class_name LeagueRules
extends RefCounted

## League regulations for one god-mode season: points, European and relegation
## places, the calendar window and the advance policy.
##
## The defaults are the v1 Premier League template (cups omitted): UCL to 1–4,
## UEL to 5th, UECL to 6th, three relegated. A save copies the template into its
## own `league_rules` row at creation, so a later seed refresh or a regulation
## change can never rewrite a season already in progress.

const DEFAULTS := {
	"win_points": 3,
	"draw_points": 1,
	"relegation_places": 3,
	"ucl_places": 4,
	"uel_places": 1,
	"uecl_places": 1,
	"matchdays": 38,
	"season_start": "2026-08-15",
	"season_end": "2027-05-23",
	"weekend_bias": 0.85,
	"midweek_matchdays": 5,
	"advance_mode": "fixture_days",
	"calendar_mode": "generated",
}

const ADVANCE_MODES := ["fixture_days", "every_day"]
const CALENDAR_MODES := ["real", "generated"]

const CREATE_SQL := (
	"CREATE TABLE IF NOT EXISTS league_rules (id INTEGER PRIMARY KEY CHECK (id = 1), "
	+ "win_points INTEGER NOT NULL, draw_points INTEGER NOT NULL, "
	+ "relegation_places INTEGER NOT NULL, ucl_places INTEGER NOT NULL, "
	+ "uel_places INTEGER NOT NULL, uecl_places INTEGER NOT NULL, "
	+ "matchdays INTEGER NOT NULL, season_start TEXT NOT NULL, season_end TEXT NOT NULL, "
	+ "weekend_bias REAL NOT NULL, midweek_matchdays INTEGER NOT NULL, "
	+ "advance_mode TEXT NOT NULL, calendar_mode TEXT NOT NULL);"
)

const UPSERT_SQL := (
	"INSERT INTO league_rules (id, win_points, draw_points, relegation_places, ucl_places, "
	+ "uel_places, uecl_places, matchdays, season_start, season_end, weekend_bias, "
	+ "midweek_matchdays, advance_mode, calendar_mode) "
	+ "VALUES (1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) "
	+ "ON CONFLICT(id) DO UPDATE SET win_points = excluded.win_points, "
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
static func defaults(calendar_mode: String = "generated", advance_mode: String = "fixture_days") -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate(true)
	out["calendar_mode"] = calendar_mode if CALENDAR_MODES.has(calendar_mode) else "generated"
	out["advance_mode"] = advance_mode if ADVANCE_MODES.has(advance_mode) else "fixture_days"
	return out

## Read the regulations copied into the save currently bound to PLDatabase.
static func read() -> Dictionary:
	var row := PLDatabase.row("SELECT * FROM league_rules WHERE id = 1;")
	if row.is_empty():
		return defaults()
	return normalize(row)

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

## Copy the regulations into the bound save.
static func write(rules: Dictionary) -> bool:
	var r := normalize(rules)
	var bindings: Array = []
	for key in COLUMNS:
		bindings.append(r[key])
	return PLDatabase.execute(UPSERT_SQL, bindings)

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
	if position <= ucl:
		return "ucl"
	if position <= ucl + uel:
		return "uel"
	if position <= ucl + uel + uecl:
		return "uecl"
	if position > 20 - down:
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
