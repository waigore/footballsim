class_name LeagueCupTie
extends RefCounted


static func simulate(season: LeagueSeason, fixture: Dictionary) -> Dictionary:
	var competition_id := str(fixture.get("competition_id", ""))
	var round_id := str(fixture.get("stage", ""))
	var tie_index := _tie_index(str(fixture.get("id", "")))
	var tie := one(competition_id, round_id, tie_index)
	if tie.is_empty():
		return {}
	var rule := LeagueCup.round_rule(competition_id, round_id)
	var seed := LeagueSeasonSim.seed_for(season, str(fixture.get("id", "")))
	var home := str(fixture.get("home_club_id", ""))
	var away := str(fixture.get("away_club_id", ""))
	var score := PoissonModel.new(seed, home, away).sample()
	var goals_home := int(tie.get("home_goals", 0))
	var goals_away := int(tie.get("away_goals", 0))
	if home == str(tie.get("home_club_id", "")):
		goals_home += score.x
		goals_away += score.y
	else:
		goals_home += score.y
		goals_away += score.x
	var last := int(fixture.get("leg", 1)) >= int(rule.get("legs", 1))
	var extra_time := false
	var pens := Vector2i(-1, -1)
	var winner := ""
	if last:
		if goals_home == goals_away and bool(rule.get("extra_time", true)):
			var et := _extra(seed + 4177, home, away)
			score += et
			if home == str(tie.get("home_club_id", "")):
				goals_home += et.x
				goals_away += et.y
			else:
				goals_home += et.y
				goals_away += et.x
			extra_time = true
		if goals_home == goals_away:
			var tie_home := str(tie.get("home_club_id", ""))
			var tie_away := str(tie.get("away_club_id", ""))
			pens = LeagueShootout.settle(seed + 7717, tie_home, tie_away)
			winner = tie_home if pens.x > pens.y else tie_away
		else:
			winner = str(tie.get("home_club_id", "")) if goals_home > goals_away \
				else str(tie.get("away_club_id", ""))
	PLDatabase.execute(
		"UPDATE cup_tie SET home_goals = ?, away_goals = ?, winner_club_id = ?, "
		+ "pens_home = ?, pens_away = ?, extra_time = ? WHERE competition_id = ? "
		+ "AND round_id = ? AND tie_index = ?;",
		[goals_home, goals_away, winner, pens.x, pens.y, 1 if extra_time else 0,
		 competition_id, round_id, tie_index])
	return {
		"score": score, "pens": pens, "extra_time": extra_time, "winner": winner,
	}


static func one(competition_id: String, round_id: String, tie_index: int) -> Dictionary:
	return PLDatabase.row(
		"SELECT * FROM cup_tie WHERE competition_id = ? AND round_id = ? AND tie_index = ?;",
		[competition_id, round_id, tie_index])


static func winner_of(competition_id: String, round_id: String) -> String:
	var row := PLDatabase.row(
		"SELECT winner_club_id FROM cup_tie WHERE competition_id = ? AND round_id = ? "
		+ "AND winner_club_id <> '' ORDER BY tie_index DESC LIMIT 1;",
		[competition_id, round_id])
	return str(row.get("winner_club_id", ""))


static func runner_up_of(competition_id: String, round_id: String) -> String:
	var row := PLDatabase.row(
		"SELECT home_club_id, away_club_id, winner_club_id FROM cup_tie "
		+ "WHERE competition_id = ? AND round_id = ? LIMIT 1;",
		[competition_id, round_id])
	if row.is_empty():
		return ""
	var winner := str(row.get("winner_club_id", ""))
	if winner == "" or winner == str(row.get("home_club_id", "")):
		return str(row.get("away_club_id", ""))
	return str(row.get("home_club_id", ""))


static func _tie_index(fixture_id: String) -> int:
	var parts := fixture_id.split("-")
	if parts.size() < 2:
		return -1
	return int(parts[parts.size() - 2])


static func _extra(seed: int, home: String, away: String) -> Vector2i:
	var goals := PoissonModel.new(seed, home, away).expected_goals()
	return Vector2i(_poisson_draw(seed + 31, goals.x / 3.0),
		_poisson_draw(seed + 61, goals.y / 3.0))


static func _poisson_draw(seed: int, mean: float) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var u := rng.randf()
	var term := exp(-mean)
	var acc := term
	var k := 0
	while u > acc and k < 8:
		k += 1
		term *= mean / float(k)
		acc += term
	return k
