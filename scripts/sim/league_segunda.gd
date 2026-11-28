class_name LeagueSegunda
extends RefCounted


const FORMAT := "segunda_four_two_leg"
const PLACES := 4


static func format(rules: Dictionary) -> bool:
	return str(rules.get("playoff_format", "")) == FORMAT


static func runs(season: LeagueSeason, competition_id: String, rules: Dictionary) -> bool:
	if not format(rules):
		return false
	return LeaguePlayoffs.runs(season, competition_id)


static func eligible(season: LeagueSeason, competition_id: String) -> Array:
	var out: Array = []
	if season == null or season.record == null:
		return out
	for row in season.record.standings.table(competition_id):
		var club: Dictionary = row
		var club_id := str(club["club_id"])
		if str(PLRepository.shared().club(club_id).get("reserve_of", "")) != "":
			continue
		out.append({
			"club_id": club_id, "name": str(club["club_name"]),
			"position": int(club["position"]), "points": int(club["points"]),
		})
	return out


static func automatic(season: LeagueSeason, competition_id: String, rules: Dictionary) -> Array:
	var out: Array = []
	for seed in ladder(season, competition_id, rules)["automatic"]:
		out.append(str((seed as Dictionary)["club_id"]))
	return out


static func ladder(season: LeagueSeason, competition_id: String, rules: Dictionary) -> Dictionary:
	var seeds := eligible(season, competition_id)
	var up := mini(int(rules.get("promotion_places", 0)), seeds.size())
	var places := mini(up + int(rules.get("promotion_playoff_places", 0)), seeds.size())
	return {"automatic": seeds.slice(0, up), "playoff": seeds.slice(up, places)}


static func build(season: LeagueSeason, competition_id: String, rules: Dictionary) -> Dictionary:
	if not runs(season, competition_id, rules):
		return {}
	var up := int(rules.get("promotion_places", 0))
	var places := int(rules.get("promotion_playoff_places", 0))
	if places < PLACES:
		return {}
	var seeds := eligible(season, competition_id)
	if seeds.size() < up + PLACES:
		return {}
	var four: Array = seeds.slice(up, up + PLACES)
	var semis := [
		_tie(season, competition_id, "SEMI-FINAL 1", four[0], four[3]),
		_tie(season, competition_id, "SEMI-FINAL 2", four[1], four[2]),
	]
	var rounds: Array = [{"name": "SEMI-FINALS", "ties": semis}]
	var one := _side(four, str(semis[0]["winner_club_id"]))
	var two := _side(four, str(semis[1]["winner_club_id"]))
	var high := one if int(one["position"]) < int(two["position"]) else two
	var low := two if high == one else one
	var final := _tie(season, competition_id, "FINAL", high, low)
	rounds.append({"name": "FINAL", "ties": [final]})
	var winner := str(final["winner_club_id"])
	var loser := str(final["loser_club_id"])
	return {
		"id": "playoffs:" + competition_id,
		"competition": competition_id,
		"format": FORMAT,
		"name": "%s — PLAY-OFFS" % PLRepository.shared().competition_name(competition_id),
		"rounds": rounds,
		"winner_club_id": winner,
		"winner_club": _club_name(winner),
		"runner_up_club_id": loser,
		"runner_up_club": _club_name(loser),
		"text": "%s beat %s in the final" % [_club_name(winner), _club_name(loser)],
	}


static func _tie(season: LeagueSeason, competition_id: String, label: String,
		high: Dictionary, low: Dictionary) -> Dictionary:
	var seed := LeaguePlayoffs._tie_seed(season, competition_id, label,
		str(high["club_id"]), str(low["club_id"]))
	var legs: Array = []
	var high_goals := 0
	var low_goals := 0
	for i in range(2):
		var high_home := i == 1
		var home := str(high["club_id"]) if high_home else str(low["club_id"])
		var away := str(low["club_id"]) if high_home else str(high["club_id"])
		var score := LeaguePlayoffs._ninety(seed + 1301 + i * 977, home, away)
		legs.append({
			"leg": i + 1, "home": home, "away": away,
			"home_name": _club_name(home), "away_name": _club_name(away),
			"home_goals": score.x, "away_goals": score.y,
		})
		high_goals += score.x if high_home else score.y
		low_goals += score.y if high_home else score.x
	var extra_time := false
	var decided := "aggregate"
	if high_goals == low_goals:
		var back: Dictionary = legs[1]
		var et := LeaguePlayoffs._extra_time(seed + 4177, str(back["home"]), str(back["away"]))
		back["home_goals"] = int(back["home_goals"]) + et.x
		back["away_goals"] = int(back["away_goals"]) + et.y
		back["extra_time"] = true
		extra_time = true
		high_goals += et.x
		low_goals += et.y
		decided = "extra time" if high_goals != low_goals else "higher place"
	var winner := str(high["club_id"]) if high_goals >= low_goals else str(low["club_id"])
	var loser := str(low["club_id"]) if winner == str(high["club_id"]) else str(high["club_id"])
	return {
		"label": label, "home": str(high["club_id"]), "away": str(low["club_id"]),
		"home_name": str(high["name"]), "away_name": str(low["name"]),
		"home_position": int(high["position"]), "away_position": int(low["position"]),
		"legs": legs, "home_goals": high_goals, "away_goals": low_goals,
		"pens_home": -1, "pens_away": -1, "extra_time": extra_time,
		"decided_by": decided, "winner_club_id": winner, "winner_club": _club_name(winner),
		"loser_club_id": loser,
		"text": _tie_text(high, low, high_goals, low_goals, decided),
	}


static func _tie_text(high: Dictionary, low: Dictionary, high_goals: int, low_goals: int,
		decided: String) -> String:
	var line := "%s %d – %d %s" % [str(high["name"]), high_goals, low_goals, str(low["name"])]
	if decided == "higher place":
		line += " (higher place)"
	elif decided == "extra time":
		line += " (extra time)"
	return line


static func _side(seeds: Array, club_id: String) -> Dictionary:
	for seed in seeds:
		if str((seed as Dictionary)["club_id"]) == club_id:
			return seed
	return seeds[seeds.size() - 1]


static func _club_name(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("name", club_id))
