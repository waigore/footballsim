class_name WikiLedger
extends RefCounted


static func repo() -> PLRepository:
	return PLRepository.shared()


static func ledger_label() -> String:
	return "SEASON" if repo().season_active() else "SNAPSHOT"


static func heading(base: String) -> String:
	if not repo().season_active():
		return base
	return "%s  ·  %s" % [base, ledger_label()]


static func record_label(snapshot: String) -> String:
	if repo().season_active():
		return "SEASON  ·  IN PLAY"
	return "SEASON  ·  %s SNAPSHOT" % snapshot


static func player_line(line: Dictionary, season_open: bool) -> Dictionary:
	if int(line.get("apps", 0)) <= 0:
		if season_open:
			return {"k": "note", "text": "NO APPEARANCES YET  ·  HE HAS NOT PLAYED IN THIS SAVE"}
		return {"k": "note", "text": "NO APPEARANCES YET  ·  PLAY A MATCH TO START THE RECORD"}
	if season_open:
		return {
			"k": "kv",
			"items": [
				["APPS", str(int(line["apps"])), true], ["GOALS", str(int(line["goals"])), true],
				["ASSISTS", str(int(line["assists"])), false],
				["CARDS", "%d / %d" % [int(line.get("yellow", 0)), int(line.get("red", 0))], false],
			],
		}
	var apps := maxf(1.0, float(line["apps"]))
	return {
		"k": "kv",
		"items": [
			["APPS", str(int(line["apps"])), true], ["GOALS", str(int(line["goals"])), true],
			["ASSISTS", str(int(line["assists"])), false], ["SHOTS", str(int(line["shots"])), false],
			["PASSES", "%d/%d" % [int(line["passes_ok"]), int(line["passes"])], false],
			["RATING", "%.1f" % (float(line["rating_sum"]) / apps), true],
		],
	}


static func competition_blocks(competition_id: String = "") -> Array:
	var top: Array = []
	for row in repo().sim_leaders(5, competition_id):
		top.append({
			"cells": [str(row["name"]), str(row["abbr"]), str(int(row["apps"])), str(int(row["goals"]))],
			"target": {"page": WikiModel.PLAYER, "id": str(row["player_id"])},
		})
	if top.is_empty():
		return []
	var label := "FOOTBALLSIM  ·  IN-SIM SCORERS"
	return [
		{"k": "section", "text": label},
		{"k": "table", "cols": ["PLAYER", "CLUB", "APPS", "GOALS"], "widths": [0.36, 0.22, 0.20, 0.22], "text_cols": [0, 1], "rows": top},
	]


static func league_blocks(competition_id: String = "") -> Array:
	return competition_blocks(competition_id)


static func club_blocks(club_id: String) -> Array:
	var season_open := repo().season_active()
	var blocks: Array = []
	if not season_open:
		var record := repo().sim_club(club_id)
		if int(record.get("played", 0)) == 0:
			return []
		blocks = [
			{"k": "section", "text": "IN FOOTBALLSIM  ·  RECORD"},
			{"k": "kv", "items": [
				["PLAYED", str(int(record["played"])), true], ["WON", str(int(record["won"])), false],
				["DRAWN", str(int(record["drawn"])), false], ["LOST", str(int(record["lost"])), false],
				["GF", str(int(record["gf"])), false], ["GA", str(int(record["ga"])), false],
				["POINTS", str(int(record["points"])), true],
			]},
		]
	var scorers: Array = []
	for row in repo().sim_scorers(club_id, 5):
		scorers.append({
			"cells": [str(row["name"]), str(int(row["apps"])), str(int(row["goals"])), str(int(row["assists"]))],
			"target": {"page": WikiModel.PLAYER, "id": str(row["player_id"])},
		})
	if not scorers.is_empty():
		if season_open:
			blocks.append({"k": "section", "text": "IN FOOTBALLSIM  ·  SEASON SCORERS"})
		blocks.append({"k": "table", "cols": ["SCORER", "APPS", "GOALS", "ASSISTS"], "widths": [0.46, 0.16, 0.19, 0.19], "text_cols": [0], "rows": scorers})
	return blocks
