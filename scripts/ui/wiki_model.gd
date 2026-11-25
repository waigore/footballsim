class_name WikiModel
extends RefCounted

## Page data for the encyclopedia. Each page is a title plus a list of blocks in
## reading order; blocks are plain dictionaries so the layout, the drawing and
## the tests all read the same description. Nothing here touches a node or a
## font, which is what keeps the dashboards testable without a screen.

const LEAGUE := "league"
const COMPETITION := "competition"
const TEAM := "team"
const PLAYER := "player"

const STYLE_LABELS := [
	["possession", "POSSESSION"], ["tempo", "TEMPO"], ["press", "PRESS"],
	["line", "LINE"], ["width", "WIDTH"], ["directness", "DIRECTNESS"],
	["crossing", "CROSSING"], ["aggression", "AGGRESSION"],
]

static func repo() -> PLRepository:
	return PLRepository.shared()

## Every page the screen can show: used to reject a bad target before pushing.
static func has_page(page: String, id: String) -> bool:
	if page == LEAGUE:
		return true
	if page == COMPETITION:
		return not repo().competition(id).is_empty()
	if page == TEAM:
		return not repo().club(id).is_empty()
	if page == PLAYER:
		return not repo().player(id).is_empty()
	return false

## A page: {title, eyebrow, subtitle, accent, blocks, crumb}.
static func page(page: String, id: String) -> Dictionary:
	if page == TEAM:
		return team_page(id)
	if page == PLAYER:
		return player_page(id)
	if page == COMPETITION:
		return competition_page(id)
	return leagues_index()

static func label(page: String, id: String) -> String:
	if page == TEAM:
		return str(repo().club(id).get("abbr", id))
	if page == PLAYER:
		return str(repo().player(id).get("name", id))
	if page == COMPETITION:
		return str(repo().competition(id).get("short_name", id))
	return "LEAGUES"

# ------------------------------------------------------------------- league --

## The index and a competition hub live in `WikiCompetitions`: the catalogue
## page here stays a dispatcher, so one page kind never owns another's blocks.
static func leagues_index() -> Dictionary:
	return WikiCompetitions.index()

static func competition_page(competition_id: String) -> Dictionary:
	return WikiCompetitions.hub(competition_id)

# --------------------------------------------------------------------- team --

static func team_page(club_id: String) -> Dictionary:
	var club := repo().club(club_id)
	if club.is_empty():
		return leagues_index()
	var meta := repo().meta()
	var table: Dictionary = club.get("table", {})
	var out := {
		"page": TEAM,
		"id": club_id,
		"title": str(club["name"]).to_upper(),
		"eyebrow": "%s  ·  %s" % [str(club["abbr"]), str(club["nickname"]).to_upper()],
		"subtitle": "%s  ·  %s  ·  %s" % [str(club["stadium"]).to_upper(), str(club["city"]).to_upper(), str(club["manager"]).to_upper()],
		"accent": club["color"],
		"blocks": [],
	}
	out["blocks"].append({"k": "chips", "items": WikiCompetitions.competition_chips_for(str(club.get("competition_id", "")))})
	out["blocks"].append({"k": "section", "text": WikiLedger.record_label(str(meta["season_label"]))})
	out["blocks"].append({
		"k": "kv",
		"items": [
			["COMPETITION", str(club.get("competition", "")), false],
			["POSITION", _or_dash(table, "position"), true],
			["POINTS", _or_dash(table, "points"), true],
			["PLAYED", _or_dash(table, "played"), false],
			["WON", _or_dash(table, "won"), false],
			["DRAWN", _or_dash(table, "drawn"), false],
			["LOST", _or_dash(table, "lost"), false],
			["GOALS FOR", _or_dash(table, "gf"), false],
			["GOALS AGAINST", _or_dash(table, "ga"), false],
			["CAPACITY", _thousands(int(club["capacity"])), false],
			["FORMATION", str(club["formation"]), false],
		],
	})
	out["blocks"].append({"k": "section", "text": "TACTICAL PROFILE"})
	var bars: Array = []
	for pair in STYLE_LABELS:
		bars.append([str(pair[1]), float(club.get("style", {}).get(pair[0], 0.5))])
	out["blocks"].append({"k": "bars", "items": bars})
	out["blocks"].append({"k": "section", "text": "SQUAD"})
	var squad_rows: Array = []
	for p in repo().squad(club_id):
		squad_rows.append({
			"cells": [str(p["number"]), str(p["name"]), str(p["pos"]), str(p["ovr"])],
			"target": {"page": PLAYER, "id": str(p["id"])},
		})
	out["blocks"].append({
		"k": "table", "cols": ["#", "PLAYER", "POS", "OVR"],
		"widths": [0.09, 0.55, 0.19, 0.17], "text_cols": [1, 2],
		"rows": squad_rows,
	})
	out["blocks"].append({"k": "section", "text": "RESULTS  ·  %s" % WikiLedger.ledger_label()})
	var results: Array = []
	for fx in repo().fixtures(club_id, 8):
		results.append({
			"cells": [
				FixtureCalendar.day_label(str(fx["kickoff"])),
				"%s %d – %d %s" % [str(fx["home_abbr"]), int(fx["home_goals"]), int(fx["away_goals"]), str(fx["away_abbr"])],
			],
			"target": {"page": TEAM, "id": str(fx["away_club_id"] if str(fx["home_club_id"]) == club_id else fx["home_club_id"])},
			"dates": {0: str(fx["kickoff"])},
		})
	if results.is_empty():
		out["blocks"].append({"k": "note", "text": "NO RESULTS YET  ·  PLAY A GAMEWEEK TO START THE RECORD"})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "FIXTURE"],
			"widths": [0.16, 0.84], "text_cols": [0, 1],
			"rows": results,
		})
	# What comes next, from the same ledger as the results above: the season's
	# remaining schedule, or the snapshot's. A fixture ahead is not a result, so
	# it never carries a score (DR-20261125-10).
	out["blocks"].append({"k": "section", "text": "NEXT FIXTURES  ·  %s" % WikiLedger.ledger_label()})
	# Only a save's ledger carries a gameweek; the snapshot ships its schedule
	# without one, so the column is there only when every row has a figure.
	var with_gw := repo().season_active()
	var next: Array = []
	for fx in repo().upcoming(club_id, 6):
		var opponent := str(fx["away_club_id"] if str(fx["home_club_id"]) == club_id else fx["home_club_id"])
		var cells := [FixtureCalendar.day_label(str(fx["kickoff"]))]
		if with_gw:
			cells.append("GW %d" % int(fx["matchday"]))
		cells.append("%s v %s" % [str(fx["home_abbr"]), str(fx["away_abbr"])])
		next.append({
			"cells": cells,
			"target": {"page": TEAM, "id": opponent},
			"dates": {0: str(fx["kickoff"])},
		})
	if next.is_empty():
		var done := "NO FIXTURES LEFT  ·  THE SEASON IS COMPLETE" if repo().season_active() \
			else "NO FIXTURES LEFT  ·  THE SNAPSHOT ENDS HERE"
		out["blocks"].append({"k": "note", "text": done})
	elif with_gw:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "GW", "FIXTURE"],
			"widths": [0.20, 0.14, 0.66], "text_cols": [0, 1, 2],
			"rows": next,
		})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "FIXTURE"],
			"widths": [0.20, 0.80], "text_cols": [0, 1],
			"rows": next,
		})
	out["blocks"].append_array(WikiLedger.club_blocks(club_id))
	return out

## A count that the snapshot may not carry: negative means "unknown", and a
## dash is honest where a zero would be a lie.
static func _count(source: Dictionary, key: String) -> String:
	var value := int(source.get(key, -1))
	return "—" if value < 0 else str(value)

static func _or_dash(table: Dictionary, key: String) -> String:
	if table.is_empty() or table.get(key) == null:
		return "—"
	return str(int(table[key]))

# ------------------------------------------------------------------- player --

static func player_page(player_id: String) -> Dictionary:
	var p := repo().player(player_id)
	if p.is_empty():
		return leagues_index()
	var club := repo().club(str(p["club_id"]))
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
		"page": PLAYER,
		"id": player_id,
		"title": str(p["name"]).to_upper(),
		"eyebrow": str(club.get("abbr", "")),
		"subtitle": identity,
		"accent": club.get("color", Color.WHITE),
		"blocks": [],
	}
	out["blocks"].append({
		"k": "kv",
		"items": [
			["OVERALL", str(int(p["ovr"])), true],
			["POSITION", str(p["pos"]), false],
			["ROLE", str(p["role"]), false],
			["HEIGHT", "%d CM" % int(p["height"]), false],
			["SQUAD", "STARTING XI" if str(p["squad"]) == "starter" else "BENCH", false],
		],
	})
	out["blocks"].append({"k": "section", "text": "ATTRIBUTES"})
	var bars: Array = []
	if str(p["role"]) == "GK":
		for pair in [["div", "DIVING"], ["han", "HANDLING"], ["kic", "KICKING"], ["ref", "REFLEXES"], ["spd", "SPEED"]]:
			bars.append([str(pair[1]), float(p["gk"].get(pair[0], 30)) / 100.0])
	else:
		for pair in [["pac", "PACE"], ["sho", "SHOOTING"], ["pas", "PASSING"], ["dri", "DRIBBLING"], ["def", "DEFENDING"], ["phy", "PHYSICAL"]]:
			bars.append([str(pair[1]), float(p[pair[0]]) / 100.0])
	out["blocks"].append({"k": "bars", "items": bars})
	out["blocks"].append({"k": "section", "text": "SEASON  ·  %s SNAPSHOT" % str(season.get("season_label", ""))})
	if int(season.get("matches", 0)) > 0:
		out["blocks"].append({
			"k": "kv",
			"items": [
				["APPS", str(int(season["matches"])), true], ["STARTS", str(int(season["starts"])), false],
				["GOALS", _count(season, "goals"), true], ["ASSISTS", _count(season, "assists"), false],
				["MINUTES", str(int(season["minutes"])), false],
				["CARDS", "%d / %d" % [int(season["yellow"]), int(season["red"])], false],
			],
		})
	else:
		out["blocks"].append({"k": "note", "text": "NO REAL-WORLD SEASON LINE IN THE SNAPSHOT  ·  RATINGS ARE THE GAME'S DATASET"})
	out["blocks"].append({"k": "section", "text": "CAREER  ·  BEST EFFORT"})
	if int(career.get("matches", 0)) > 0:
		out["blocks"].append({
			"k": "kv",
			"items": [
				["APPS", str(int(career["matches"])), true], ["GOALS", _count(career, "goals"), true],
				["ASSISTS", _count(career, "assists"), false],
			],
		})
	else:
		out["blocks"].append({"k": "note", "text": "NO CAREER TOTALS IN THE SNAPSHOT"})
	var season_open := repo().season_active()
	out["blocks"].append({"k": "section", "text": WikiLedger.heading("IN FOOTBALLSIM")})
	out["blocks"].append(WikiLedger.player_line(sim, season_open))
	out["blocks"].append({"k": "chips", "items": [
		{
			"text": str(club.get("name", "")).to_upper(),
			"target": {"page": TEAM, "id": str(p["club_id"])},
			"accent": _hex(club.get("color", Color.WHITE)),
		},
		{
			"text": str(club.get("competition", "")),
			"target": {"page": COMPETITION, "id": str(club.get("competition_id", ""))},
			"accent": _hex(Color("#f7c948")),
		},
	]})
	return out

# ---------------------------------------------------------------- shared bit --

static func _hex(col) -> String:
	var c: Color = col if col is Color else Color.WHITE
	return c.to_html(false)

static func _thousands(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
