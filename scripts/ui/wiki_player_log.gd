class_name WikiPlayerLog
extends RefCounted


const LIMIT := 10


static func blocks(player_id: String, club_id: String, limit: int = LIMIT) -> Array:
	if player_id == "" or club_id == "" or not LeagueLedger.bound():
		return []
	var played := LeagueLedger.player_events(player_id, club_id, limit + 1)
	var out: Array = [{"k": "section", "text": "IN FOOTBALLSIM  ·  MATCH BY MATCH"}]
	if played.is_empty():
		out.append({"k": "note", "text":
			"NO GOALS OR CARDS YET  ·  HE HAS NOT SCORED, ASSISTED OR BEEN BOOKED IN THIS SAVE"})
		return out
	var rows: Array = []
	for fx in played.slice(0, limit):
		var venue := "A"
		if bool(fx["home"]):
			venue = "H"
		rows.append({
			"cells": [
				FixtureCalendar.day_label(str(fx["kickoff"])),
				"GW %d" % int(fx["matchday"]),
				"%s (%s)" % [str(fx["opponent_abbr"]), venue],
				"%d – %d" % [int(fx["home_goals"]), int(fx["away_goals"])],
				parts(fx["events"]),
			],
			"target": {"page": WikiModel.TEAM, "id": str(fx["opponent_id"])},
			"dates": {0: str(fx["kickoff"])},
		})
	out.append({
		"k": "table", "cols": ["DATE", "GW", "OPPONENT", "SCORE", "HIS PART"],
		"widths": [0.18, 0.10, 0.20, 0.13, 0.39], "text_cols": [0, 1, 2, 4], "rows": rows,
	})
	if played.size() > limit:
		out.append({"k": "note", "text":
			"EARLIER MATCHES NOT LISTED  ·  ONLY THE MOST RECENT ARE SHOWN"})
	return out


static func parts(events: Array) -> String:
	var counts := {}
	for e in events:
		var kind := str(e.get("kind", ""))
		if kind == "goal" and bool(e.get("penalty", false)):
			counts["pen"] = int(counts.get("pen", 0)) + 1
		counts[kind] = int(counts.get(kind, 0)) + 1
	var out: Array = []
	var goals := int(counts.get("goal", 0))
	if goals > 0:
		var goal_text := "%d GOALS" % goals
		if goals == 1:
			goal_text = "1 GOAL"
		var pens := int(counts.get("pen", 0))
		if pens > 0:
			goal_text += " (%d PEN)" % pens
		out.append(goal_text)
	var assists := int(counts.get("assist", 0))
	if assists > 0:
		var assist_text := "%d ASSISTS" % assists
		if assists == 1:
			assist_text = "1 ASSIST"
		out.append(assist_text)
	if int(counts.get("yellow", 0)) > 0:
		out.append("BOOKED")
	if int(counts.get("red", 0)) > 0:
		out.append("SENT OFF")
	if int(counts.get("injury", 0)) > 0:
		out.append("INJURED")
	return "  ·  ".join(PackedStringArray(out))
