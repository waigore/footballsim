class_name LeagueSettle
extends RefCounted


static func auto(record: LeagueRecord, fixture_id: String, home: String, away: String,
		home_xi: Array, away_xi: Array, events: Array, seed: int,
		date: String, matchday: int) -> void:
	var lines := {}
	for side in [[home_xi, home], [away_xi, away]]:
		for p in side[0]:
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
	for side in [[home_xi, home], [away_xi, away]]:
		for p in side[0]:
			var id := str(p["id"])
			rows.append({"player_id": id, "club_id": str(side[1]), "line": lines[id]})
	record.report.add_player_lines(rows)
	var sides := [
		{"club_id": home, "rows": _cards(home_xi, lines), "events": _events_for(events, home)},
		{"club_id": away, "rows": _cards(away_xi, lines), "events": _events_for(events, away)},
	]
	SeasonAvailability.apply_fixture(matchday, date, sides, seed)


static func watch(record: LeagueRecord, engine, events: Array, seed: int,
		date: String, matchday: int) -> void:
	var rows: Array = []
	var sides := {}
	for p in engine.players:
		var club := str(engine.teams[p.team]["id"])
		rows.append({
			"player_id": str(p.key), "club_id": club,
			"line": {
				"apps": 1, "goals": int(p.stats.get("goals", 0)),
				"assists": int(p.stats.get("assists", 0)), "yellow": int(p.yellow),
				"red": 1 if p.red else 0,
			},
		})
		if not sides.has(club):
			sides[club] = {"club_id": club, "rows": [], "events": []}
		var row: Dictionary = sides[club]
		row["rows"].append({"player_id": str(p.key), "yellow": int(p.yellow),
			"red": 1 if p.red else 0})
		if bool(p.injured):
			row["events"].append({"kind": "injury", "player_id": str(p.key), "club_id": club})
	record.report.add_player_lines(rows)
	SeasonAvailability.apply_fixture(matchday, date, sides.values(), seed)

static func _cards(xi: Array, lines: Dictionary) -> Array:
	var out: Array = []
	for p in xi:
		var line: Dictionary = lines.get(str(p["id"]), {})
		out.append({"player_id": str(p["id"]), "yellow": int(line.get("yellow", 0)),
			"red": int(line.get("red", 0))})
	return out

static func _events_for(events: Array, club_id: String) -> Array:
	var out: Array = []
	for e in events:
		if str(e.get("club_id", "")) == club_id:
			out.append(e)
	return out
