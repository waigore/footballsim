class_name WikiLeague
extends RefCounted


static func page(competition_id: String = "") -> Dictionary:
	var comp := PLCompetitions.one(
		competition_id if competition_id != "" else PLCompetitions.default_id())
	var comp_id := str(comp.get("id", ""))
	var meta := WikiModel.repo().meta()
	var season := str(comp.get("season_label", meta.get("season_label", "")))
	var name := str(comp.get("name", meta.get("league_name", "Premier League")))
	var out := {
		"page": WikiModel.LEAGUE,
		"id": comp_id,
		"title": name.to_upper(),
		"eyebrow": "%s  ·  %s" % [str(comp.get("short_name", name)).to_upper(), season],
		"subtitle": "%d CLUBS  ·  SNAPSHOT " % int(comp.get("clubs", 0)),
		"snapshot": str(meta.get("snapshot_date", "")),
		"accent": Color("#f7c948"),
		"blocks": [],
	}
	out["blocks"].append(WikiCompetitions.index(comp_id))
	out["blocks"].append({"k": "section", "text": "LEAGUE TABLE"})
	var rows: Array = []
	for row in WikiModel.repo().table(comp_id):
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
		"rows": leader_rows(6, "goals", comp_id),
	})
	out["blocks"].append({"k": "section", "text": "CLUB INDEX"})
	out["blocks"].append({"k": "chips", "items": club_chips(comp_id)})
	var results: Array = []
	for fx in WikiModel.repo().fixtures("", 10, comp_id):
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
	var claims_ledger := PLCompetitions.season_owns(comp_id) \
		or (not LeagueLedger.bound() and comp_id == PLCompetitions.default_id())
	if claims_ledger:
		out["blocks"].append_array(WikiLedger.league_blocks(comp_id))
	out["blocks"].append({"k": "note", "text": "SELECTED BY CLUB OR PLAYER  ·  ESC OR BACK RETURNS  ·  REAL DATA: %s" % str(meta.get("source", ""))})
	return out


static func leader_rows(limit: int, stat: String, competition_id: String = "") -> Array:
	var rows: Array = []
	for row in WikiModel.repo().leaders(limit, stat, competition_id):
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
	for id in WikiModel.repo().club_ids(competition_id):
		var club := WikiModel.repo().club(id)
		items.append({
			"text": str(club.get("abbr", id)),
			"target": {"page": WikiModel.TEAM, "id": str(id)},
			"accent": WikiModel.hex(club.get("color", Color.WHITE)),
		})
	return items
