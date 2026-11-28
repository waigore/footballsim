class_name WikiCup
extends RefCounted


const ACCENT := "#f7c948"


static func page(competition_id: String) -> Dictionary:
	var comp := PLRepository.shared().competition(competition_id)
	var name := str(comp.get("name", competition_id))
	var season := str(comp.get("season_label", PLRepository.shared().meta().get("season_label", "")))
	var bound := LeagueLedger.bound()
	var stage := LeagueCupState.stage(competition_id) if bound else ""
	var honour := LeagueCupState.honours(competition_id) if bound else {}
	var out := {
		"page": WikiModel.CUP, "id": competition_id, "title": name.to_upper(),
		"eyebrow": "%s  ·  %s" % [str(comp.get("short_name", name)).to_upper(), season],
		"subtitle": subtitle(competition_id, stage, honour, bound),
		"snapshot": str(PLRepository.shared().meta().get("snapshot_date", "")),
		"accent": Color(ACCENT), "blocks": [],
	}
	out["blocks"].append(WikiCompetitions.index(competition_id))
	out["blocks"].append({"k": "kv", "items": facts(competition_id, stage, honour, bound)})
	out["blocks"].append({"k": "section", "text": "THE DRAW"})
	out["blocks"].append({"k": "note", "text": draw_note(competition_id, stage)})
	if not bound:
		out["blocks"].append({"k": "note",
			"text": "OPEN A SEASON TO READ THIS CUP'S BRACKET  ·  THE SHIPPED SEED CARRIES NO TIES"})
		out["blocks"].append({"k": "note",
			"text": "A CUP HAS NO TABLE  ·  ITS STANDING IS ITS BRACKET"})
		return out
	out["blocks"].append({"k": "section", "text": "BRACKET"})
	for row in LeagueCupState.bracket(competition_id):
		var round_row: Dictionary = row
		var rows := tie_rows(competition_id, round_row)
		if rows.is_empty():
			continue
		out["blocks"].append({"k": "section",
			"text": "%s  ·  %s" % [str(round_row["name"]).to_upper(),
				FixtureCalendar.day_label(str(round_row.get("date", "")))]})
		out["blocks"].append({
			"k": "table", "cols": ["HOME", "", "AWAY", "SCORE"], "widths": [0.38, 0.05, 0.37, 0.20],
			"text_cols": [0, 2], "rows": rows,
		})
	var ahead := fixtures_ahead(competition_id)
	out["blocks"].append({"k": "section", "text": "FIXTURES AHEAD"})
	if ahead.is_empty():
		out["blocks"].append({"k": "note", "text": "NO CUP NIGHT IS STILL TO COME"})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "HOME", "AWAY"], "widths": [0.20, 0.42, 0.38],
			"text_cols": [0, 1, 2], "rows": ahead,
		})
	out["blocks"].append({"k": "section", "text": "LATEST RESULTS"})
	var played := results(competition_id)
	if played.is_empty():
		out["blocks"].append({"k": "note", "text": "NO CUP TIE HAS BEEN PLAYED YET"})
	else:
		out["blocks"].append({
			"k": "table", "cols": ["DATE", "HOME", "", "AWAY"], "widths": [0.18, 0.34, 0.14, 0.34],
			"text_cols": [0, 1, 3], "rows": played,
		})
	out["blocks"].append({"k": "note",
		"text": "A CUP HAS NO TABLE  ·  ITS STANDING IS ITS BRACKET"})
	return out


static func subtitle(competition_id: String, stage: String, honour: Dictionary,
		bound: bool = true) -> String:
	if not honour.is_empty():
		return "WINNER  ·  %s" % str(honour.get("winner_name", ""))
	if not bound:
		return "%d ROUNDS" % LeagueCup.rounds(competition_id).size()
	if stage == "":
		return "NOT DRAWN YET"
	return "%s  ·  %d CLUBS IN" % [LeagueCupView.stage_name(competition_id, stage),
		LeagueCupView.clubs_left(competition_id)]


static func facts(competition_id: String, stage: String, honour: Dictionary,
		bound: bool = true) -> Array:
	var rule := LeagueCup.round_rule(competition_id, stage)
	var next := LeagueCupView.next_date(competition_id) if bound else ""
	var items: Array = [
		["KIND", LeagueCup.kind(competition_id).to_upper()],
		["ROUNDS", str(LeagueCup.rounds(competition_id).size())],
		["STAGE", LeagueCupView.stage_name(competition_id, stage) if stage != "" else "NOT DRAWN"],
	]
	if not rule.is_empty():
		items.append(["LEGS", "TWO" if int(rule.get("legs", 1)) > 1 else "ONE"])
		items.append(["EXTRA TIME", "YES" if bool(rule.get("extra_time", false)) else "PENALTIES ONLY"])
	if next != "":
		items.append(["NEXT NIGHT", FixtureCalendar.day_label(next)])
	elif not bound:
		items.append(["BRACKET", "READS THE OPEN SEASON"])
	if not honour.is_empty():
		items.append(["RUNNER-UP", str(honour.get("runner_up_name", ""))])
	return items


static func draw_note(competition_id: String, stage: String = "") -> String:
	var rule := LeagueCup.round_rule(competition_id, stage)
	var parts: Array = []
	if bool(rule.get("regional", false)):
		parts.append("NORTH AND SOUTH POTS")
	if str(rule.get("host", "draw")) == "lower":
		parts.append("THE LOWER CLUB HOSTS")
	elif str(rule.get("host", "draw")) == "neutral":
		parts.append("A NEUTRAL VENUE")
	return "  ·  ".join(PackedStringArray(parts)) if not parts.is_empty() \
		else "AN OPEN DRAW FROM THE SEASON SEED"


static func tie_rows(competition_id: String, round_row: Dictionary) -> Array:
	var rows: Array = []
	for tie in round_row.get("ties", []):
		var data: Dictionary = tie
		var score := LeagueCupView.score_line(data)
		rows.append({
			"cells": [str(data.get("home_name", "")), "v", str(data.get("away_name", "")),
				score if score != "" else "TO PLAY"],
			"target": {"page": WikiModel.TEAM, "id": str(data.get("home", ""))},
			"club_cell": 0,
		})
	return rows


static func fixtures_ahead(competition_id: String) -> Array:
	var rows: Array = []
	for row in PLDatabase.rows(
			"SELECT f.*, h.name AS home_name, a.name AS away_name FROM league_fixture f "
			+ "JOIN club h ON h.id = f.home_club_id JOIN club a ON a.id = f.away_club_id "
			+ "WHERE f.competition_id = ? AND f.status <> 'played' "
			+ "ORDER BY f.kickoff, f.kickoff_time LIMIT 8;", [competition_id]):
		rows.append({
			"cells": [FixtureCalendar.day_label(str(row["kickoff"])), str(row["home_name"]),
				str(row["away_name"])],
			"target": {"page": WikiModel.TEAM, "id": str(row["home_club_id"])},
			"dates": {0: str(row["kickoff"])}, "club_cell": 1,
		})
	return rows


static func results(competition_id: String) -> Array:
	var rows: Array = []
	for row in PLDatabase.rows(
			"SELECT f.*, h.name AS home_name, a.name AS away_name FROM league_fixture f "
			+ "JOIN club h ON h.id = f.home_club_id JOIN club a ON a.id = f.away_club_id "
			+ "WHERE f.competition_id = ? AND f.status = 'played' "
			+ "ORDER BY f.kickoff DESC, f.id DESC LIMIT 10;", [competition_id]):
		rows.append({
			"cells": [FixtureCalendar.day_label(str(row["kickoff"])), str(row["home_name"]),
				"%d – %d" % [int(row["home_goals"]), int(row["away_goals"])], str(row["away_name"])],
			"target": {"page": WikiModel.TEAM, "id": str(row["home_club_id"])},
			"club_cell": 1,
		})
	return rows
