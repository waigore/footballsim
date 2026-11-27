class_name LeagueRelegation
extends RefCounted


const TOP := "BL"
const SECOND := "BL2"


static func runs(actives: Array) -> bool:
	return actives.has(TOP) and actives.has(SECOND)


static func build(season: LeagueSeason) -> Dictionary:
	if season == null or season.save == null or season.record == null:
		return {}
	if not runs(season.save.actives):
		return {}
	if season.record.fixtures.unplayed() > 0:
		return {}
	var top_rules := season.save.rules_for(TOP)
	var second_rules := season.save.rules_for(SECOND)
	var top_table: Array = season.record.standings.table(TOP)
	var second_table: Array = season.record.standings.table(SECOND)
	var top_place := int(top_rules.get("clubs", 18)) - int(top_rules.get("relegation_places", 2))
	var second_place := int(second_rules.get("promotion_places", 2)) + 1
	if top_table.size() < top_place or second_table.size() < second_place:
		return {}
	var top_club := str((top_table[top_place - 1] as Dictionary)["club_id"])
	var second_club := str((second_table[second_place - 1] as Dictionary)["club_id"])
	var seed := int(season.rng.seed)
	var legs := _legs(season, seed, top_club, second_club)
	var aggregate := _aggregate(legs, top_club)
	var winner := ""
	var decided_by := "aggregate"
	if int(aggregate["top"]) == int(aggregate["second"]):
		decided_by = "penalties"
		var pens := _shootout(seed, top_club, second_club)
		aggregate["pens_top"] = int(pens[0])
		aggregate["pens_second"] = int(pens[1])
		winner = top_club if int(pens[0]) > int(pens[1]) else second_club
	else:
		winner = top_club if int(aggregate["top"]) > int(aggregate["second"]) else second_club
	var comp := PLRepository.shared().competition(TOP)
	return {
		"id": "relegation",
		"competition": TOP,
		"name": "%s — RELEGATION" % str(comp.get("short_name", "BUNDESLIGA")),
		"top_club_id": top_club,
		"top_club": _club_name(top_club),
		"top_position": top_place,
		"second_club_id": second_club,
		"second_club": _club_name(second_club),
		"second_position": second_place,
		"legs": legs,
		"top_goals": int(aggregate["top"]),
		"second_goals": int(aggregate["second"]),
		"pens_top": int(aggregate.get("pens_top", -1)),
		"pens_second": int(aggregate.get("pens_second", -1)),
		"winner_club_id": winner,
		"winner_club": _club_name(winner),
		"loser_club_id": second_club if winner == top_club else top_club,
		"decided_by": decided_by,
		"text": _text(aggregate, decided_by, winner, top_club, second_club),
	}


static func _legs(season: LeagueSeason, seed: int, top_club: String, second_club: String) -> Array:
	var out: Array = []
	var pairings := [[top_club, second_club], [second_club, top_club]]
	for i in range(pairings.size()):
		var home := str(pairings[i][0])
		var away := str(pairings[i][1])
		var model := PoissonModel.new(seed + 1301 + i * 977, home, away)
		var score := model.sample()
		out.append({
			"leg": i + 1, "home": home, "away": away,
			"home_name": _club_name(home), "away_name": _club_name(away),
			"home_goals": int(score.x), "away_goals": int(score.y),
		})
	return out

static func _aggregate(legs: Array, top_club: String) -> Dictionary:
	var top := 0
	var second := 0
	for leg in legs:
		if str(leg["home"]) == top_club:
			top += int(leg["home_goals"])
			second += int(leg["away_goals"])
		else:
			top += int(leg["away_goals"])
			second += int(leg["home_goals"])
	return {"top": top, "second": second}


static func _shootout(seed: int, top_club: String, second_club: String) -> Vector2i:
	return LeagueShootout.settle(seed, top_club, second_club)

static func _club_name(club_id: String) -> String:
	var club := PLRepository.shared().club(club_id)
	return str(club.get("name", club_id))

static func _text(aggregate: Dictionary, decided_by: String, winner: String,
		top_club: String, second_club: String) -> String:
	var win_name := _club_name(winner)
	var outcome := "stay up" if winner == top_club else "go up"
	var line := "%s %d – %d %s" % [_club_name(top_club), int(aggregate["top"]),
		int(aggregate["second"]), _club_name(second_club)]
	if decided_by == "penalties":
		line += " (%d–%d pens)" % [int(aggregate.get("pens_top", 0)),
			int(aggregate.get("pens_second", 0))]
	return "%s — %s %s" % [line, win_name, outcome]
