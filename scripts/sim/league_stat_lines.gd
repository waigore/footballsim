class_name LeagueStatLines
extends RefCounted

## The player lines behind one auto-simmed fixture: a side's XI all played 90
## minutes, and goals, assists and cards come off the synthetic event rows, so
## the season chart reads the same report the player saw.
##
## Kept out of `LeagueSeason` (which is at its P3 size ratchet) and pure apart
## from the record it writes through.

static func write(record: LeagueRecord, events: Array, sides: Dictionary,
		clubs: Dictionary) -> void:
	if record == null:
		return
	var lines := {}
	for side in ["home", "away"]:
		for p in sides[side]:
			lines[str(p["id"])] = {"apps": 1, "goals": 0, "assists": 0, "yellow": 0, "red": 0}
	for e in events:
		var id := str(e.get("player_id", ""))
		if not lines.has(id):
			continue
		var kind := str(e.get("kind", ""))
		if kind == "goal":
			lines[id]["goals"] += 1
		elif kind == "assist":
			lines[id]["assists"] += 1
		elif kind == "yellow":
			lines[id]["yellow"] += 1
		elif kind == "red":
			lines[id]["red"] += 1
	var rows: Array = []
	for side in ["home", "away"]:
		for p in sides[side]:
			var id := str(p["id"])
			rows.append({"player_id": id, "club_id": str(clubs[side]), "line": lines[id]})
	record.add_player_lines(rows)
