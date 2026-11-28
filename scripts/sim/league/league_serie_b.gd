class_name LeagueSerieB
extends RefCounted


const FORMAT := "serie_b_six"


static func format(rules: Dictionary) -> bool:
	return str(rules.get("playoff_format", "")) == FORMAT


static func skips(season: LeagueSeason, competition_id: String, rules: Dictionary) -> bool:
	var gap := int(rules.get("promotion_skip_gap", 0))
	if gap <= 0 or season == null or season.record == null:
		return false
	var table: Array = season.record.standings.table(competition_id)
	var up := int(rules.get("promotion_places", 0))
	if table.size() < up + 2:
		return false
	var third := int((table[up] as Dictionary)["points"])
	var fourth := int((table[up + 1] as Dictionary)["points"])
	return third - fourth > gap


static func build(season: LeagueSeason, competition_id: String, rules: Dictionary) -> Dictionary:
	var up := int(rules.get("promotion_places", 0))
	var seeds := LeaguePlayoffs._seeds(season, competition_id, up,
		int(rules.get("promotion_playoff_places", 0)))
	if seeds.size() < 6:
		return {}
	if skips(season, competition_id, rules):
		return _skipped(season, competition_id, seeds)
	var rounds: Array = []
	var prelims := [
		_preliminary(season, competition_id, "PRELIMINARY 1", seeds[2], seeds[5]),
		_preliminary(season, competition_id, "PRELIMINARY 2", seeds[3], seeds[4]),
	]
	rounds.append({"name": "PRELIMINARIES", "ties": prelims})
	var semis := [
		_two_legs(season, competition_id, rules, "SEMI-FINAL 1", seeds[0], _side(seeds, prelims[1]), false),
		_two_legs(season, competition_id, rules, "SEMI-FINAL 2", seeds[1], _side(seeds, prelims[0]), false),
	]
	rounds.append({"name": "SEMI-FINALS", "ties": semis})
	var one: Dictionary = _side(seeds, semis[0])
	var two: Dictionary = _side(seeds, semis[1])
	var high := one if int(one["position"]) < int(two["position"]) else two
	var low := two if high == one else one
	var final := _two_legs(season, competition_id, rules, "FINAL", high, low,
		int(high["points"]) == int(low["points"]))
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


static func playout(season: LeagueSeason, competition_id: String, rules: Dictionary) -> Dictionary:
	if season == null or season.record == null or season.save == null:
		return {}
	if season.save.actives.is_empty() or not season.save.actives.has(competition_id):
		return {}
	if int(rules.get("playout_places", 0)) < 2:
		return {}
	if season.record.fixtures.unplayed() > 0:
		return {}
	var table: Array = season.record.standings.table(competition_id)
	var down := int(rules.get("relegation_places", 0))
	var playout := int(rules.get("playout_places", 0))
	var first := table.size() - down - playout
	if first < 0:
		return {}
	var high: Dictionary = table[first]
	var low: Dictionary = table[first + 1]
	var legs: Array = []
	var high_goals := 0
	var low_goals := 0
	var seed := int(season.rng.seed) + _hash("playout|" + competition_id)
	for i in range(2):
		var high_home := i == 1
		var home := str(high["club_id"]) if high_home else str(low["club_id"])
		var away := str(low["club_id"]) if high_home else str(high["club_id"])
		var score := LeaguePlayoffs._ninety(seed + 2063 + i * 883, home, away)
		legs.append({
			"leg": i + 1, "home": home, "away": away,
			"home_name": _club_name(home), "away_name": _club_name(away),
			"home_goals": score.x, "away_goals": score.y,
		})
		high_goals += score.x if high_home else score.y
		low_goals += score.y if high_home else score.x
	var survivor := str(high["club_id"]) if high_goals >= low_goals else str(low["club_id"])
	var relegated := str(low["club_id"]) if survivor == str(high["club_id"]) else str(high["club_id"])
	var decided := "aggregate" if high_goals != low_goals else "higher place"
	return {
		"id": "playout:" + competition_id,
		"competition": competition_id,
		"name": "%s — PLAY-OUT" % PLRepository.shared().competition_name(competition_id),
		"high_club_id": str(high["club_id"]),
		"high_club": str(high["club_name"]),
		"high_position": int(high["position"]),
		"low_club_id": str(low["club_id"]),
		"low_club": str(low["club_name"]),
		"low_position": int(low["position"]),
		"legs": legs,
		"high_goals": high_goals,
		"low_goals": low_goals,
		"decided_by": decided,
		"winner_club_id": survivor,
		"winner_club": _club_name(survivor),
		"relegated_club_id": relegated,
		"relegated_club": _club_name(relegated),
		"relegated_position": int(low["position"]) if relegated == str(low["club_id"]) else int(high["position"]),
		"text": "%s %d – %d %s — %s %s" % [
			str(high["club_name"]), high_goals, low_goals, str(low["club_name"]),
			_club_name(relegated), "relegated",
		],
	}


static func playouts(season: LeagueSeason) -> Dictionary:
	var out := {}
	if season == null or season.save == null:
		return out
	for cid in season.save.actives:
		var tie := playout(season, str(cid), season.save.rules_for(str(cid)))
		if not tie.is_empty():
			out[str(cid)] = tie
	return out


static func _skipped(season: LeagueSeason, competition_id: String, seeds: Array) -> Dictionary:
	var third: Dictionary = seeds[0]
	var fourth: Dictionary = seeds[1]
	var club_id := str(third["club_id"])
	return {
		"id": "playoffs:" + competition_id,
		"competition": competition_id,
		"format": FORMAT,
		"skipped": true,
		"name": "%s — PLAY-OFFS" % PLRepository.shared().competition_name(competition_id),
		"rounds": [],
		"winner_club_id": club_id,
		"winner_club": _club_name(club_id),
		"runner_up_club_id": str(fourth["club_id"]),
		"runner_up_club": _club_name(str(fourth["club_id"])),
		"text": "%s go up on the 14-point rule" % _club_name(club_id),
	}


static func _preliminary(season: LeagueSeason, competition_id: String,
		label: String, high: Dictionary, low: Dictionary) -> Dictionary:
	var seed := _seed_of(season, competition_id, label, str(high["club_id"]), str(low["club_id"]))
	var score := LeaguePlayoffs._ninety(seed + 1301, str(high["club_id"]), str(low["club_id"]))
	var high_goals: int = score.x
	var low_goals: int = score.y
	var extra_time := false
	var decided := "ninety"
	if high_goals == low_goals:
		var et := LeaguePlayoffs._extra_time(seed + 4177, str(high["club_id"]), str(low["club_id"]))
		high_goals += et.x
		low_goals += et.y
		extra_time = true
		decided = "extra time" if high_goals != low_goals else "higher place"
	var winner := str(high["club_id"]) if high_goals >= low_goals else str(low["club_id"])
	var leg := {
		"leg": 1, "home": str(high["club_id"]), "away": str(low["club_id"]),
		"home_name": str(high["name"]), "away_name": str(low["name"]),
		"home_goals": high_goals, "away_goals": low_goals,
	}
	if extra_time:
		leg["extra_time"] = true
	return _tie_dict(label, high, low, [leg], high_goals, low_goals, extra_time, decided,
		winner, Vector2i(-1, -1))


static func _two_legs(season: LeagueSeason, competition_id: String, rules: Dictionary,
		label: String, high: Dictionary, low: Dictionary, equal_points: bool) -> Dictionary:
	var seed := _seed_of(season, competition_id, label, str(high["club_id"]), str(low["club_id"]))
	var legs: Array = []
	var high_goals := 0
	var low_goals := 0
	var high_points := 0
	var low_points := 0
	for i in range(2):
		var high_home := i == 1
		var home := str(high["club_id"]) if high_home else str(low["club_id"])
		var away := str(low["club_id"]) if high_home else str(high["club_id"])
		var score := LeaguePlayoffs._ninety(seed + 1301 + i * 977, home, away)
		var home_goals: int = score.x
		var away_goals: int = score.y
		var high_for: int = home_goals if high_home else away_goals
		var low_for: int = away_goals if high_home else home_goals
		high_points += LeagueRules.points(high_for, low_for, rules)
		low_points += LeagueRules.points(low_for, high_for, rules)
		high_goals += high_for
		low_goals += low_for
		legs.append({
			"leg": i + 1, "home": home, "away": away,
			"home_name": _club_name(home), "away_name": _club_name(away),
			"home_goals": home_goals, "away_goals": away_goals,
		})
	var extra_time := false
	var pens := Vector2i(-1, -1)
	var winner := ""
	var decided := "points"
	if high_points != low_points:
		winner = str(high["club_id"]) if high_points > low_points else str(low["club_id"])
	elif high_goals != low_goals:
		decided = "goal difference"
		winner = str(high["club_id"]) if high_goals > low_goals else str(low["club_id"])
	elif equal_points:
		decided = "extra time"
		extra_time = true
		var final_leg: Dictionary = legs[1]
		var et := LeaguePlayoffs._extra_time(seed + 4177, str(final_leg["home"]),
			str(final_leg["away"]))
		final_leg["home_goals"] = int(final_leg["home_goals"]) + et.x
		final_leg["away_goals"] = int(final_leg["away_goals"]) + et.y
		final_leg["extra_time"] = true
		if str(final_leg["home"]) == str(high["club_id"]):
			high_goals += et.x
			low_goals += et.y
		else:
			low_goals += et.x
			high_goals += et.y
		if high_goals == low_goals:
			decided = "penalties"
			pens = LeagueShootout.settle(seed + 7717, str(high["club_id"]), str(low["club_id"]))
			winner = str(high["club_id"]) if pens.x > pens.y else str(low["club_id"])
		else:
			winner = str(high["club_id"]) if high_goals > low_goals else str(low["club_id"])
	else:
		decided = "higher place"
		winner = str(high["club_id"])
	return _tie_dict(label, high, low, legs, high_goals, low_goals, extra_time, decided,
		winner, pens)


static func _tie_dict(label: String, high: Dictionary, low: Dictionary, legs: Array,
		high_goals: int, low_goals: int, extra_time: bool, decided: String,
		winner: String, pens: Vector2i) -> Dictionary:
	var loser := str(low["club_id"]) if winner == str(high["club_id"]) else str(high["club_id"])
	var text := "%s %d – %d %s" % [str(high["name"]), high_goals, low_goals, str(low["name"])]
	if pens.x >= 0:
		text += " (%d–%d pens)" % [pens.x, pens.y]
	elif decided == "higher place":
		text += " (higher place)"
	elif extra_time:
		text += " (extra time)"
	return {
		"label": label, "home": str(high["club_id"]), "away": str(low["club_id"]),
		"home_name": str(high["name"]), "away_name": str(low["name"]),
		"home_position": int(high["position"]), "away_position": int(low["position"]),
		"legs": legs, "home_goals": high_goals, "away_goals": low_goals,
		"pens_home": pens.x, "pens_away": pens.y, "extra_time": extra_time,
		"decided_by": decided, "winner_club_id": winner, "winner_club": _club_name(winner),
		"loser_club_id": loser, "text": text,
	}


static func _side(seeds: Array, tie: Dictionary) -> Dictionary:
	var winner := str(tie["winner_club_id"])
	for seed in seeds:
		if str((seed as Dictionary)["club_id"]) == winner:
			return seed
	return seeds[seeds.size() - 1]


static func _seed_of(season: LeagueSeason, competition_id: String, label: String,
		high_id: String, low_id: String) -> int:
	return LeaguePlayoffs._tie_seed(season, competition_id, label, high_id, low_id)


static func _hash(key: String) -> int:
	var h := 0
	for i in range(key.length()):
		h = int((h * 31 + key.unicode_at(i)) % 2147483647)
	return h


static func _club_name(club_id: String) -> String:
	return str(PLRepository.shared().club(club_id).get("name", club_id))
