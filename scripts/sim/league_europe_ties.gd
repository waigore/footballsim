class_name LeagueEuropeTies
extends RefCounted


static func rounds(competition_id: String) -> Array:
	var out: Array = []
	for row in LeagueUefa.rounds(competition_id):
		var round_id := str((row as Dictionary).get("id", ""))
		var state := "ahead"
		if LeagueUefa.has_stage(competition_id, round_id):
			state = "done" if LeagueUefa.stage_complete(competition_id, round_id) else "live"
		out.append({
			"id": round_id, "label": LeagueEurope.round_short(round_id),
			"name": LeagueEurope.round_label(round_id), "state": state,
			"legs": int((row as Dictionary).get("legs", 1)),
			"date": str((row as Dictionary).get("date", "")),
			"ties": _tie_count(competition_id, round_id),
		})
	return out


static func ties(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	if round_id == "" or not LeagueUefa.has_stage(competition_id, round_id):
		return out
	var drops := _drop_map(competition_id, round_id)
	var arrived := _dropped_in(competition_id, round_id)
	var legs := _legs(competition_id, round_id)
	for row in PLDatabase.rows(
			"SELECT * FROM cup_tie WHERE competition_id = ? AND round_id = ? ORDER BY tie_index;",
			[competition_id, round_id]):
		var tie: Dictionary = row
		var home := str(tie.get("home_club_id", ""))
		var away := str(tie.get("away_club_id", ""))
		var winner := str(tie.get("winner_club_id", ""))
		var loser := home
		if winner == home:
			loser = away
		var report := ""
		var leg_lines: Array = []
		var leg_rows: Array = legs.get(int(tie.get("tie_index", 0)), [])
		for i in range(leg_rows.size()):
			var leg: Dictionary = leg_rows[i]
			leg_lines.append(leg_line(leg, i + 1))
			if str(leg.get("status", "")) == "played":
				report = str(leg.get("id", ""))
		var drop := ""
		if winner != "":
			drop = str(drops.get(loser, ""))
		out.append({
			"index": int(tie.get("tie_index", 0)), "home": home, "away": away,
			"home_name": LeagueEurope.club_name(home), "away_name": LeagueEurope.club_name(away),
			"played": winner != "", "winner": winner,
			"report": report, "leg_lines": leg_lines,
			"drop": drop, "arrived": str(arrived.get(home, str(arrived.get(away, "")))),
			"score_line": LeagueEurope.score_line(tie),
		})
	return out


static func leg_line(leg: Dictionary, number: int) -> String:
	if str(leg.get("status", "")) != "played":
		return "L%d  —" % number
	return "L%d  %d–%d" % [number, int(leg.get("home_goals", 0)), int(leg.get("away_goals", 0))]


static func tonight(save: LeagueSave) -> Array:
	var out: Array = []
	if save == null:
		return out
	var ids := LeagueEurope.active(save)
	var rows := PLDatabase.rows(
		"SELECT f.*, h.name AS home_name, a.name AS away_name FROM league_fixture f "
		+ "JOIN club h ON h.id = f.home_club_id JOIN club a ON a.id = f.away_club_id "
		+ "WHERE f.kickoff = ? ORDER BY f.competition_id, f.kickoff_time, f.id;",
		[save.current_date()])
	for row in rows:
		var fx: Dictionary = row
		if not ids.has(str(fx.get("competition_id", ""))):
			continue
		out.append(fx)
	return out


static func _tie_count(competition_id: String, round_id: String) -> int:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ?;",
		[competition_id, round_id])
	return int(row.get("n", 0))


static func _legs(competition_id: String, round_id: String) -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT id, leg, home_club_id, away_club_id, home_goals, away_goals, status, kickoff "
			+ "FROM league_fixture WHERE competition_id = ? AND stage = ? ORDER BY leg, id;",
			[competition_id, round_id]):
		var fx: Dictionary = row
		var index := _tie_index(str(fx.get("id", "")))
		if not out.has(index):
			out[index] = []
		(out[index] as Array).append(fx)
	return out


static func _tie_index(fixture_id: String) -> int:
	var parts := fixture_id.split("-")
	if parts.size() < 2:
		return -1
	return int(parts[parts.size() - 2])


static func _losers(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT home_club_id, away_club_id, winner_club_id FROM cup_tie "
			+ "WHERE competition_id = ? AND round_id = ? AND winner_club_id <> '' "
			+ "ORDER BY tie_index;", [competition_id, round_id]):
		var winner := str(row.get("winner_club_id", ""))
		var home := str(row.get("home_club_id", ""))
		var loser := home
		if winner == home:
			loser = str(row.get("away_club_id", ""))
		out.append(loser)
	return out


static func _drop_map(competition_id: String, round_id: String) -> Dictionary:
	var out := {}
	var rules := LeagueUefa.drops(competition_id, round_id)
	if rules.is_empty():
		return out
	var losers := _losers(competition_id, round_id)
	var at := 0
	for row in rules:
		var dest := str((row as Dictionary).get("to", ""))
		var dest_round := str((row as Dictionary).get("round", ""))
		var count := int((row as Dictionary).get("count", 0))
		for i in range(count):
			if at >= losers.size():
				break
			out[str(losers[at])] = "↓ %s %s" % [dest, LeagueEurope.round_short(dest_round)]
			at += 1
	return out


static func _dropped_in(competition_id: String, round_id: String) -> Dictionary:
	var out := {}
	var source := _source_of(competition_id, round_id)
	if source == "":
		return out
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' AND role = ?;", [competition_id, "drop:" + round_id]):
		out[str(row.get("member_id", ""))] = "← %s" % source
	return out


static func _source_of(competition_id: String, round_id: String) -> String:
	for other in LeagueUefa.IDS:
		for round_row in LeagueUefa.rounds(str(other)):
			var source_round := str((round_row as Dictionary).get("id", ""))
			for rule_row in LeagueUefa.drops(str(other), source_round):
				var rule: Dictionary = rule_row
				if str(rule.get("to", "")) == competition_id \
						and str(rule.get("round", "")) == round_id:
					return "%s %s" % [other, LeagueEurope.round_short(source_round)]
	return ""
