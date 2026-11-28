class_name LeagueEuropeTies
extends RefCounted


static func qualifying(competition_id: String) -> Array:
	var out: Array = []
	for rid in LeagueUefa.round_ids(competition_id):
		var round_id := str(rid)
		if round_id == LeagueUefa.LEAGUE_STAGE or LeagueEurope.KO_ROUNDS.has(round_id):
			continue
		if not LeagueUefa.has_stage(competition_id, round_id):
			continue
		var ties := rows(competition_id, round_id, drop_map(competition_id, round_id),
			arrivals(competition_id, round_id))
		if ties.is_empty():
			continue
		var rule := LeagueUefa.round_rule(competition_id, round_id)
		out.append({"id": round_id, "title": LeagueEurope.round_title(competition_id, round_id),
			"date": str(rule.get("date", "")), "legs": int(rule.get("legs", 2)),
			"complete": LeagueUefa.stage_complete(competition_id, round_id), "ties": ties})
	return out


static func bracket(competition_id: String) -> Array:
	var out: Array = []
	for round_id in LeagueEurope.KO_ROUNDS:
		if not LeagueUefa.has_stage(competition_id, round_id):
			continue
		var rule := LeagueUefa.round_rule(competition_id, round_id)
		out.append({"id": round_id, "title": LeagueEurope.round_title(competition_id, round_id),
			"date": str(rule.get("date", "")), "legs": int(rule.get("legs", 1)),
			"complete": LeagueUefa.stage_complete(competition_id, round_id),
			"ties": rows(competition_id, round_id, {}, {})})
	return out


static func rows(competition_id: String, round_id: String, drops: Dictionary,
		arrivals_by_club: Dictionary) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT * FROM cup_tie WHERE competition_id = ? AND round_id = ? ORDER BY tie_index;",
			[competition_id, round_id]):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		var winner := str(row["winner_club_id"])
		var tie_index := int(row["tie_index"])
		var legs := legs(competition_id, round_id, tie_index)
		var played := winner != ""
		var home_goals := int(row["home_goals"])
		var away_goals := int(row["away_goals"])
		out.append({
			"index": tie_index, "home": home, "away": away,
			"home_name": LeagueUefa.club_name(home), "away_name": LeagueUefa.club_name(away),
			"home_goals": home_goals, "away_goals": away_goals, "winner": winner,
			"pens_home": int(row["pens_home"]), "pens_away": int(row["pens_away"]),
			"extra_time": int(row["extra_time"]) == 1, "played": played, "legs": legs,
			"fixture": open_leg(legs), "report_leg": last_played(legs),
			"watched": watched(legs),
			"agg": agg(home, away, home_goals, away_goals, played),
			"drop": {} if not played or winner == "" else _one(drops, away if winner == home else home),
			"arrival": _arrival(arrivals_by_club, home, away),
		})
	return out


static func _one(drops: Dictionary, club_id: String) -> Dictionary:
	return (drops.get(club_id, {}) as Dictionary).duplicate()


static func _arrival(arrivals_by_club: Dictionary, home: String, away: String) -> Dictionary:
	for club_id in [home, away]:
		if arrivals_by_club.has(club_id):
			var row: Dictionary = (arrivals_by_club[club_id] as Dictionary).duplicate()
			row["club"] = club_id
			return row
	return {}


static func agg(home: String, away: String, home_goals: int, away_goals: int,
		played: bool) -> String:
	if not played:
		return "—"
	if home_goals == away_goals:
		return "%d–%d" % [home_goals, away_goals]
	return "%d–%d" % [home_goals, away_goals] if home_goals > away_goals \
		else "%d–%d" % [away_goals, home_goals]


static func legs(competition_id: String, round_id: String, tie_index: int) -> Array:
	var out: Array = []
	for leg in range(1, 3):
		var fixture_id := "uefa-%s-%s-%02d-%d" % [competition_id, round_id, tie_index, leg]
		var row := PLDatabase.row("SELECT * FROM league_fixture WHERE id = ?;", [fixture_id])
		if row.is_empty():
			continue
		out.append({"id": fixture_id, "home": str(row["home_club_id"]),
			"away": str(row["away_club_id"]), "home_goals": int(row["home_goals"]),
			"away_goals": int(row["away_goals"]), "played": str(row["status"]) == "played",
			"watched": int(row["watched"]), "leg": leg, "kickoff": str(row["kickoff"])})
	return out


static func open_leg(legs_in: Array) -> String:
	for leg in legs_in:
		if not bool((leg as Dictionary)["played"]):
			return str((leg as Dictionary)["id"])
	if legs_in.is_empty():
		return ""
	return str((legs_in[legs_in.size() - 1] as Dictionary)["id"])


static func last_played(legs_in: Array) -> String:
	var out := ""
	for leg in legs_in:
		if bool((leg as Dictionary)["played"]):
			out = str((leg as Dictionary)["id"])
	return out


static func watched(legs_in: Array) -> int:
	for leg in legs_in:
		if not bool((leg as Dictionary)["played"]):
			return int((leg as Dictionary).get("watched", 0))
	return 0


static func losers(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT home_club_id, away_club_id, winner_club_id FROM cup_tie "
			+ "WHERE competition_id = ? AND round_id = ? AND winner_club_id <> '' ORDER BY tie_index;",
			[competition_id, round_id]):
		var winner := str(row["winner_club_id"])
		out.append(str(row["away_club_id"]) if winner == str(row["home_club_id"])
			else str(row["home_club_id"]))
	return out


static func drop_map(competition_id: String, round_id: String) -> Dictionary:
	var out := {}
	var rules := LeagueUefa.drops(competition_id, round_id)
	var out_goers := losers(competition_id, round_id)
	var at := 0
	for rule in rules:
		for i in range(int((rule as Dictionary).get("count", 0))):
			if at >= out_goers.size():
				break
			out[out_goers[at]] = (rule as Dictionary).duplicate()
			at += 1
	return out


static func arrivals(competition_id: String, round_id: String) -> Dictionary:
	var out := {}
	for source in LeagueUefa.IDS:
		for rid in LeagueUefa.round_ids(str(source)):
			var drops := drop_map(str(source), str(rid))
			for club_id in drops:
				var rule: Dictionary = drops[club_id]
				if str(rule.get("to", "")) != competition_id:
					continue
				if str(rule.get("round", "")) != round_id:
					continue
				out[str(club_id)] = {"competition": str(source), "round": str(rid)}
	return out


static func drop_label(rule: Dictionary) -> String:
	if rule.is_empty():
		return ""
	return "↓ %s %s" % [str(rule.get("to", "")), LeagueEurope.badge(str(rule.get("round", "")))]


static func arrival_label(arrival: Dictionary) -> String:
	if arrival.is_empty():
		return ""
	return "← %s %s" % [str(arrival.get("competition", "")),
		LeagueEurope.badge(str(arrival.get("round", "")))]
