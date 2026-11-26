class_name WikiModel
extends RefCounted

## Page data for the encyclopedia. Each page is a title plus a list of blocks in
## reading order; blocks are plain dictionaries so the layout, the drawing and
## the tests all read the same description. Nothing here touches a node or a
## font, which is what keeps the dashboards testable without a screen.

const LEAGUE := "league"
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
		return id == "" or PLCompetitions.exists(id)
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
	return league_page(id)

static func label(page: String, id: String) -> String:
	if page == TEAM:
		return str(repo().club(id).get("abbr", id))
	if page == PLAYER:
		return str(repo().player(id).get("name", id))
	var comp := PLCompetitions.one(id if id != "" else PLCompetitions.default_id())
	return str(comp.get("short_name", "LEAGUE")).to_upper()

# ------------------------------------------------------------------- league --

## One competition's hub. `competition_id` empty means the file's default
## competition (the Premier League in the shipped seed), so every existing
## caller keeps its page.
static func league_page(competition_id: String = "") -> Dictionary:
	var comp := PLCompetitions.one(
		competition_id if competition_id != "" else PLCompetitions.default_id())
	var comp_id := str(comp.get("id", ""))
	var meta := repo().meta()
	# A file with no competition row at all (an old cache) still reads: the
	# metadata is the snapshot's own name for its league.
	var season := str(comp.get("season_label", meta.get("season_label", "")))
	var name := str(comp.get("name", meta.get("league_name", "Premier League")))
	var out := {
		"page": LEAGUE,
		"id": comp_id,
		"title": name.to_upper(),
		"eyebrow": "%s  ·  %s" % [str(comp.get("short_name", name)).to_upper(), season],
		# The snapshot date is drawn as its own date label (#99), so the sheet can
		# give it the weekday hint without hunting for it in the subtitle.
		"subtitle": "%d CLUBS  ·  SNAPSHOT " % int(comp.get("clubs", 0)),
		"snapshot": str(meta.get("snapshot_date", "")),
		"accent": Color("#f7c948"),
		"blocks": [],
	}
	out["blocks"].append(WikiCompetitions.index(comp_id))
	out["blocks"].append({"k": "section", "text": "LEAGUE TABLE"})
	var rows: Array = []
	for row in repo().table(comp_id):
		rows.append({
			"cells": [
				str(int(row["position"])), str(row["club_abbr"]),
				str(int(row["played"])), str(int(row["won"])), str(int(row["drawn"])),
				str(int(row["lost"])), str(int(row["gf"])), str(int(row["ga"])),
				str(int(row["points"])),
			],
			"target": {"page": TEAM, "id": str(row["club_id"])},
			"accent": str(row.get("club_color", "")),
			"club_cell": 1,
		})
	out["blocks"].append({
		"k": "table",
		"cols": ["#", "CLUB", "P", "W", "D", "L", "GF", "GA", "PTS"],
		"widths": [0.05, 0.27, 0.09, 0.09, 0.09, 0.09, 0.10, 0.10, 0.12],
		"text_cols": [1],
		"rows": rows,
	})
	out["blocks"].append({"k": "section", "text": "TOP SCORERS  ·  SNAPSHOT"})
	out["blocks"].append({
		"k": "table", "cols": ["PLAYER", "CLUB", "APPS", "GOALS"],
		"widths": [0.36, 0.22, 0.20, 0.22], "text_cols": [0, 1],
		"rows": _leader_rows(6, "goals", comp_id),
	})
	out["blocks"].append({"k": "section", "text": "CLUB INDEX"})
	out["blocks"].append({"k": "chips", "items": _club_chips(comp_id)})
	var results: Array = []
	for fx in repo().fixtures("", 10, comp_id):
		results.append({
			"cells": [
				FixtureCalendar.day_label(str(fx["kickoff"])), str(fx["home_abbr"]),
				"%d – %d" % [int(fx["home_goals"]), int(fx["away_goals"])], str(fx["away_abbr"]),
			],
			"target": {"page": TEAM, "id": str(fx["home_club_id"])},
			"dates": {0: str(fx["kickoff"])}, "club_cell": 1,
		})
	out["blocks"].append({"k": "section", "text": "LATEST RESULTS  ·  %s" % WikiLedger.ledger_label()})
	if results.is_empty():
		out["blocks"].append({"k": "note", "text": "NO RESULTS YET  ·  PLAY A GAMEWEEK TO START THE RECORD"})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "HOME", "", "AWAY"],
			"widths": [0.16, 0.28, 0.22, 0.34], "text_cols": [0, 1, 3],
			"rows": results,
		})
	# A season's own block only belongs on the competition it is playing, and the
	# single-match ledger (no season open) only on the file's own competition: an
	# inactive competition reads the snapshot alone.
	var claims_ledger := PLCompetitions.season_owns(comp_id) \
		or (not LeagueLedger.bound() and comp_id == PLCompetitions.default_id())
	if claims_ledger:
		out["blocks"].append_array(WikiLedger.league_blocks())
	out["blocks"].append({"k": "note", "text": "SELECTED BY CLUB OR PLAYER  ·  ESC OR BACK RETURNS  ·  REAL DATA: %s" % str(meta.get("source", ""))})
	return out

static func _leader_rows(limit: int, stat: String, competition_id: String = "") -> Array:
	var rows: Array = []
	for row in repo().leaders(limit, stat, competition_id):
		rows.append({
			"cells": [
				str(row["name"]), str(row["abbr"]), str(int(row["matches"])),
				str(int(row["goals"] if stat == "goals" else row["assists"])),
			],
			"target": {"page": PLAYER, "id": str(row["player_id"])},
		})
	return rows

static func _club_chips(competition_id: String = "") -> Array:
	var items: Array = []
	for id in repo().club_ids(competition_id):
		var club := repo().club(id)
		items.append({
			"text": str(club.get("abbr", id)),
			"target": {"page": TEAM, "id": str(id)},
			"accent": _hex(club.get("color", Color.WHITE)),
		})
	return items

# --------------------------------------------------------------------- team --

static func team_page(club_id: String) -> Dictionary:
	var club := repo().club(club_id)
	if club.is_empty():
		return league_page()
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
	out["blocks"].append(WikiCompetitions.link(str(club.get("competition", ""))))
	out["blocks"].append({"k": "section", "text": WikiLedger.record_label(str(meta["season_label"]))})
	out["blocks"].append({
		"k": "kv",
		"items": [
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
		return league_page()
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
	out["blocks"].append({"k": "chips", "items": [{
		"text": str(club.get("name", "")).to_upper(),
		"target": {"page": TEAM, "id": str(p["club_id"])},
		"accent": _hex(club.get("color", Color.WHITE)),
	}]})
	out["blocks"].append(WikiCompetitions.link(str(club.get("competition", ""))))
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
