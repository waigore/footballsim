class_name WikiCompetitions
extends RefCounted

## The encyclopedia's competition pages: the leagues index and one hub per
## competition. Split out of `WikiModel` so the page catalogue stays inside its
## size budget; the shapes are the same blocks `WikiBody` already draws, and the
## cross-links point at `WikiModel.TEAM` / `WikiModel.PLAYER`.
##
## An index plus a hub per competition is the multi-competition shape: a future
## cup or international is another row in `competition`, never a rewrite.

static func repo() -> PLRepository:
	return PLRepository.shared()

## The front page: every competition the seed (or the open save) carries, with a
## way into each hub.
static func index() -> Dictionary:
	var meta := repo().meta()
	var season := str(meta.get("season_label", ""))
	var comps: Array = repo().active_competitions()
	var out := {
		"page": WikiModel.LEAGUE,
		"title": "LEAGUES",
		"eyebrow": "FOOTBALLSIM  ·  %s" % season,
		# The snapshot date is drawn as its own date label (#99), so the sheet can
		# give it the weekday hint without hunting for it in the subtitle.
		"subtitle": "%d COMPETITIONS  ·  SNAPSHOT " % comps.size(),
		"snapshot": str(meta.get("snapshot_date", "")),
		"accent": Color("#f7c948"),
		"blocks": [],
	}
	out["blocks"].append({"k": "section", "text": "COMPETITIONS"})
	out["blocks"].append({"k": "chips", "items": competition_chips(comps)})
	for comp in comps:
		var cid := str(comp["id"])
		out["blocks"].append({"k": "section", "text": "%s  ·  TABLE" % str(comp["name"]).to_upper()})
		out["blocks"].append(table_block(cid, 6))
		out["blocks"].append({"k": "section", "text": "%s  ·  TOP SCORERS" % str(comp["short_name"])})
		out["blocks"].append({
			"k": "table", "cols": ["PLAYER", "CLUB", "APPS", "GOALS"],
			"widths": [0.36, 0.22, 0.20, 0.22], "text_cols": [0, 1],
			"rows": leader_rows(5, "goals", cid),
		})
	out["blocks"].append({"k": "note", "text": "PICK A COMPETITION FOR ITS FULL HUB  ·  ESC OR BACK RETURNS  ·  REAL DATA: %s" % str(meta.get("source", ""))})
	return out

## One competition's hub: table, scorer charts, results and its clubs.
static func hub(competition_id: String) -> Dictionary:
	var comp := repo().competition(competition_id)
	if comp.is_empty():
		return index()
	var meta := repo().meta()
	var season := str(meta.get("season_label", ""))
	var clubs: Array = repo().club_ids(competition_id)
	var out := {
		"page": WikiModel.COMPETITION,
		"id": competition_id,
		"title": str(comp["name"]).to_upper(),
		"eyebrow": "%s  ·  %s" % [str(comp["short_name"]), season],
		"subtitle": "%d CLUBS  ·  %s " % [clubs.size(), WikiLedger.ledger_label()],
		"snapshot": str(meta.get("snapshot_date", "")),
		"accent": Color("#f7c948"),
		"blocks": [],
	}
	out["blocks"].append({"k": "section", "text": "LEAGUE TABLE"})
	out["blocks"].append(table_block(competition_id, 20))
	out["blocks"].append({"k": "section", "text": "TOP SCORERS  ·  %s" % WikiLedger.ledger_label()})
	out["blocks"].append({
		"k": "table", "cols": ["PLAYER", "CLUB", "APPS", "GOALS"],
		"widths": [0.36, 0.22, 0.20, 0.22], "text_cols": [0, 1],
		"rows": leader_rows(6, "goals", competition_id),
	})
	out["blocks"].append({"k": "section", "text": "TOP ASSISTS  ·  %s" % WikiLedger.ledger_label()})
	out["blocks"].append({
		"k": "table", "cols": ["PLAYER", "CLUB", "APPS", "ASSISTS"],
		"widths": [0.36, 0.22, 0.20, 0.22], "text_cols": [0, 1],
		"rows": leader_rows(6, "assists", competition_id),
	})
	var results: Array = []
	for fx in repo().fixtures("", 10, competition_id):
		results.append({
			"cells": [
				FixtureCalendar.day_label(str(fx["kickoff"])), str(fx["home_abbr"]),
				"%d – %d" % [int(fx["home_goals"]), int(fx["away_goals"])], str(fx["away_abbr"]),
			],
			"target": {"page": WikiModel.TEAM, "id": str(fx["home_club_id"])},
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
	out["blocks"].append({"k": "section", "text": "CLUB INDEX"})
	out["blocks"].append({"k": "chips", "items": club_chips(competition_id)})
	out["blocks"].append_array(WikiLedger.competition_blocks(competition_id))
	out["blocks"].append({"k": "note", "text": "SELECTED BY CLUB OR PLAYER  ·  ESC OR BACK RETURNS  ·  REAL DATA: %s" % str(meta.get("source", ""))})
	return out

## One competition's standings rows, limited to the top `limit`.
static func table_block(competition_id: String, limit: int) -> Dictionary:
	var rows: Array = []
	for row in repo().table(competition_id):
		if rows.size() >= limit:
			break
		rows.append({
			"cells": [
				str(int(row["position"])), str(row["club_abbr"]),
				str(int(row["played"])), str(int(row["won"])), str(int(row["drawn"])),
				str(int(row["lost"])), str(int(row["gf"])), str(int(row["ga"])),
				str(int(row["points"])),
			],
			"target": {"page": WikiModel.TEAM, "id": str(row["club_id"])},
			"accent": str(row.get("club_color", "")),
			"club_cell": 1,
		})
	return {
		"k": "table",
		"cols": ["#", "CLUB", "P", "W", "D", "L", "GF", "GA", "PTS"],
		"widths": [0.05, 0.27, 0.09, 0.09, 0.09, 0.09, 0.10, 0.10, 0.12],
		"text_cols": [1],
		"rows": rows,
	}

static func leader_rows(limit: int, stat: String, competition_id: String = "") -> Array:
	var rows: Array = []
	for row in repo().leaders(limit, stat, competition_id):
		rows.append({
			"cells": [
				str(row["name"]), str(row["abbr"]), str(int(row["matches"])),
				str(int(row["goals"] if stat == "goals" else row["assists"])),
			],
			"target": {"page": WikiModel.PLAYER, "id": str(row["player_id"])},
		})
	return rows

static func club_chips(competition_id: String = "") -> Array:
	var items: Array = []
	for id in repo().club_ids(competition_id):
		var club := repo().club(id)
		items.append({
			"text": str(club.get("abbr", id)),
			"target": {"page": WikiModel.TEAM, "id": str(id)},
			"accent": _hex(club.get("color", Color.WHITE)),
		})
	return items

static func competition_chips(comps: Array) -> Array:
	var items: Array = []
	for comp in comps:
		items.append({
			"text": str(comp.get("short_name", comp.get("name", ""))),
			"target": {"page": WikiModel.COMPETITION, "id": str(comp["id"])},
			"accent": _hex(Color("#f7c948")),
		})
	return items

## One chip back to the competition a club plays in (empty when it has none).
static func competition_chips_for(competition_id: String) -> Array:
	if competition_id == "":
		return []
	return competition_chips([repo().competition(competition_id)])

static func _hex(col) -> String:
	var c: Color = col if col is Color else Color.WHITE
	return c.to_html(false)
