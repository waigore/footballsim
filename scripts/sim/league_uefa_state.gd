class_name LeagueUefaState
extends RefCounted


static func start(season: LeagueSeason) -> void:
	if season == null or season.save == null:
		return
	for competition_id in LeagueUefa.active_ids(season.save):
		resume(season, str(competition_id))


static func resume(season: LeagueSeason, competition_id: String) -> void:
	if not LeagueUefa.has_stage(competition_id, LeagueUefa.first_round(competition_id)):
		var first := LeagueUefa.first_round(competition_id)
		draw_stage(season, competition_id, first,
			LeagueUefa.entrants(competition_id, first))
		return
	for round_id in LeagueUefa.round_ids(competition_id):
		if not LeagueUefa.has_stage(competition_id, round_id):
			continue
		if not LeagueUefa.stage_complete(competition_id, round_id):
			continue
		advance(season, competition_id, round_id)


static func advance(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	if round_id == LeagueUefa.LEAGUE_STAGE:
		_seed_knockout(season, competition_id)
		return
	_route_drops(season, competition_id, round_id)
	var next := LeagueUefa.after(competition_id, round_id)
	if next == "" or LeagueUefa.has_stage(competition_id, next):
		return
	if next == LeagueUefa.LEAGUE_STAGE:
		draw_league_phase(season, competition_id)
		return
	draw_stage(season, competition_id, next, _pool_for(competition_id, next))


static func _pool_for(competition_id: String, round_id: String) -> Array:
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	var pool: Array = []
	for feeder in (rule.get("feeds", []) as Array):
		pool.append_array(_winners(competition_id, str(feeder)))
	pool.append_array(LeagueUefa.entrants(competition_id, round_id))
	pool.append_array(_dropped_into(competition_id, round_id))
	return pool


static func _winners(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT winner_club_id FROM cup_tie WHERE competition_id = ? AND round_id = ? "
			+ "AND winner_club_id <> '' ORDER BY tie_index;", [competition_id, round_id]):
		out.append(str(row["winner_club_id"]))
	return out


static func _losers(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT home_club_id, away_club_id, winner_club_id FROM cup_tie "
			+ "WHERE competition_id = ? AND round_id = ? AND winner_club_id <> '' "
			+ "ORDER BY tie_index;", [competition_id, round_id]):
		var winner := str(row["winner_club_id"])
		out.append(str(row["away_club_id"]) if winner == str(row["home_club_id"])
			else str(row["home_club_id"]))
	return out


static func _dropped_into(competition_id: String, round_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT member_id FROM competition_member WHERE competition_id = ? "
			+ "AND member_kind = 'club' AND role = ? ORDER BY member_id;",
			[competition_id, "drop:" + round_id]):
		out.append(str(row["member_id"]))
	return out


static func _route_drops(season: LeagueSeason, competition_id: String, round_id: String) -> void:
	var rules := LeagueUefa.drops(competition_id, round_id)
	if rules.is_empty():
		return
	var losers := _losers(competition_id, round_id)
	var at := 0
	for row in rules:
		var target := str((row as Dictionary).get("to", ""))
		var target_round := str((row as Dictionary).get("round", ""))
		var count := int((row as Dictionary).get("count", 0))
		for i in range(count):
			if at >= losers.size():
				break
			add_drop(target, target_round, str(losers[at]))
			at += 1


static func add_drop(competition_id: String, round_id: String, club_id: String) -> void:
	PLDatabase.execute(
		"INSERT OR IGNORE INTO competition_member (competition_id, member_kind, member_id, role) "
		+ "VALUES (?, 'club', ?, ?);", [competition_id, club_id, "drop:" + round_id])


static func draw_stage(season: LeagueSeason, competition_id: String, round_id: String,
		pool: Array) -> bool:
	if season == null or season.save == null:
		return false
	var ids := _unique(pool)
	if ids.size() < 2:
		return false
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	var pairs := LeagueCupDraw.settle(season, competition_id, round_id, ids)
	if pairs.is_empty():
		return false
	var position := LeagueUefa.round_ids(competition_id).find(round_id) + 1
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_round (competition_id, round_id, position, status) "
		+ "VALUES (?, ?, ?, 'open');", [competition_id, round_id, position])
	var legs := int(rule.get("legs", 2))
	for i in range(pairs.size()):
		var pair: Dictionary = pairs[i]
		var home := str(pair["home"])
		var away := str(pair["away"])
		PLDatabase.execute(
			"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, "
			+ "home_club_id, away_club_id, winner_club_id, home_goals, away_goals, "
			+ "pens_home, pens_away, extra_time) VALUES (?, ?, ?, ?, ?, '', 0, 0, -1, -1, 0);",
			[competition_id, round_id, i, home, away])
		for leg in range(1, legs + 1):
			_install(season, competition_id, round_id, str(rule.get("date", "")),
				str(rule.get("second_leg", "")), position, i, leg, home, away)
	season.save.set_status("in_progress")
	return true


static func _install(season: LeagueSeason, competition_id: String, round_id: String,
		first_date: String, second_date: String, position: int, tie_index: int,
		leg: int, home: String, away: String) -> void:
	var date := first_date if leg == 1 else second_date
	if date == "":
		date = FixtureCalendar.add_days(first_date, 7 * (leg - 1))
	var fixture_home := home if leg == 1 else away
	var fixture_away := away if leg == 1 else home
	PLDatabase.execute(
		"INSERT OR REPLACE INTO league_fixture (id, competition_id, matchday, kickoff, "
		+ "kickoff_time, home_club_id, away_club_id, status, watched, suggested, stage, leg) "
		+ "VALUES (?, ?, ?, ?, ?, ?, ?, 'pending', 0, 0, ?, ?);",
		["uefa-%s-%s-%02d-%d" % [competition_id, round_id, tie_index, leg],
		 competition_id, position, date,
		 FixtureCalendar.KICKOFF_TIMES[(tie_index + leg) % FixtureCalendar.KICKOFF_TIMES.size()],
		 fixture_home, fixture_away, round_id, leg])


static func _unique(pool: Array) -> Array:
	var seen := {}
	var out: Array = []
	for club_id in pool:
		var key := str(club_id)
		if key == "" or seen.has(key):
			continue
		seen[key] = true
		out.append(key)
	return out


static func draw_league_phase(season: LeagueSeason, competition_id: String) -> bool:
	return LeagueUefaLeaguePhase.draw(season, competition_id)


static func _seed_knockout(season: LeagueSeason, competition_id: String) -> void:
	LeagueUefaKnockout.seed(season, competition_id)


static func after_played(season: LeagueSeason, fixture: Dictionary) -> void:
	var competition_id := str(fixture.get("competition_id", ""))
	if not LeagueUefa.is_continental(competition_id):
		return
	var round_id := str(fixture.get("stage", ""))
	if round_id == "" or not LeagueUefa.stage_complete(competition_id, round_id):
		return
	if round_id == LeagueUefa.LEAGUE_STAGE:
		advance(season, competition_id, round_id)
		return
	LeagueUefaKnockout.after_round(season, competition_id, round_id)
	advance(season, competition_id, round_id)


static func record_engine(season: LeagueSeason, fixture: Dictionary, home_goals: int,
		away_goals: int) -> void:
	if season == null or season.save == null:
		return
	var competition_id := str(fixture.get("competition_id", ""))
	var round_id := str(fixture.get("stage", ""))
	if not LeagueUefa.is_continental(competition_id) or round_id == LeagueUefa.LEAGUE_STAGE:
		return
	var tie_index := _tie_index(str(fixture.get("id", "")))
	var tie := LeagueCupTie.one(competition_id, round_id, tie_index)
	if tie.is_empty():
		return
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	var seed := LeagueSeasonSim.seed_for(season, str(fixture.get("id", "")))
	var home := str(fixture.get("home_club_id", ""))
	var tie_home := str(tie.get("home_club_id", ""))
	var tie_away := str(tie.get("away_club_id", ""))
	var goals_home := int(tie.get("home_goals", 0))
	var goals_away := int(tie.get("away_goals", 0))
	if home == tie_home:
		goals_home += home_goals
		goals_away += away_goals
	else:
		goals_home += away_goals
		goals_away += home_goals
	var last := int(fixture.get("leg", 1)) >= int(rule.get("legs", 1))
	var extra_time := false
	var pens := Vector2i(-1, -1)
	var winner := ""
	if last:
		if goals_home == goals_away and bool(rule.get("extra_time", true)):
			var et := _extra(seed + 4177, home, str(fixture.get("away_club_id", "")))
			if home == tie_home:
				goals_home += et.x
				goals_away += et.y
			else:
				goals_home += et.y
				goals_away += et.x
			extra_time = true
		if goals_home == goals_away:
			pens = LeagueShootout.settle(seed + 7717, tie_home, tie_away)
			winner = tie_home if pens.x > pens.y else tie_away
		else:
			winner = tie_home if goals_home > goals_away else tie_away
	PLDatabase.execute(
		"UPDATE cup_tie SET home_goals = ?, away_goals = ?, winner_club_id = ?, "
		+ "pens_home = ?, pens_away = ?, extra_time = ? WHERE competition_id = ? "
		+ "AND round_id = ? AND tie_index = ?;",
		[goals_home, goals_away, winner, pens.x, pens.y, 1 if extra_time else 0,
		 competition_id, round_id, tie_index])


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
