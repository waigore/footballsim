class_name WikiLedger
extends RefCounted

## The Footballsim blocks on the encyclopedia's pages, and the headings that say
## which ledger they belong to.
##
## A save owns its own ledger (`LeagueLedger`), and the encyclopedia is the place
## a player looks up what has happened, so while a season is open every in-sim
## reading on these pages comes from it (DR-20261125-08). The real-world snapshot
## keeps its own sections, labelled SNAPSHOT, so the two readings never wear the
## same name.

static func repo() -> PLRepository:
	return PLRepository.shared()

## Which ledger a page's figures come from: the season being played, or the
## snapshot the encyclopedia ships with.
static func ledger_label() -> String:
	return "SEASON" if repo().season_active() else "SNAPSHOT"

## A block heading that says which ledger answered: "IN FOOTBALLSIM  ·  SEASON".
## The season is not named: the hub already carries the save's name, and one
## season is open at a time (DR-20261125-08).
static func heading(base: String) -> String:
	if not repo().season_active():
		return base
	return "%s  ·  %s" % [base, ledger_label()]

## The season block's heading: this save's season in play, or the snapshot's
## label for the real-world figures.
static func record_label(snapshot: String) -> String:
	if repo().season_active():
		return "SEASON  ·  IN PLAY"
	return "SEASON  ·  %s SNAPSHOT" % snapshot

## A player's Footballsim line. The season keeps apps, goals, assists and cards
## on both paths; it keeps no per-match shots or rating, so the season block does
## not promise them.
static func player_line(line: Dictionary, season_open: bool) -> Dictionary:
	if int(line.get("apps", 0)) <= 0:
		if season_open:
			return {"k": "note", "text": "NO SEASON LINE YET  ·  HE HAS NOT PLAYED IN THIS SAVE"}
		return {"k": "note", "text": "NO MATCHES RECORDED YET  ·  PLAY A MATCH TO START THIS LEDGER"}
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

## A competition hub's in-sim block: that league's scorer chart, or the
## single-match one. Absent (not an empty table) until someone has scored.
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

## The hub's in-sim block, scoped to the competition it belongs to.
static func league_blocks(competition_id: String = "") -> Array:
	return competition_blocks(competition_id)

## A club page's in-sim blocks. While a season is open the record is already in
## the page's season header, so only the club's scorer chart is appended here.
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
