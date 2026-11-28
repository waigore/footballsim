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
		pool.append_array(LeagueCupTie.winners(competition_id, str(feeder)))
	pool.append_array(LeagueUefa.entrants(competition_id, round_id))
	pool.append_array(_dropped_into(competition_id, round_id))
	return pool


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
	var ids := LeagueCupDraw.unique(pool)
	if ids.size() < 2:
		return false
	var rule := LeagueUefa.round_rule(competition_id, round_id)
	var pairs := LeagueCupDraw.settle(season, competition_id, round_id, ids)
	if pairs.is_empty():
		return false
	var position := LeagueUefa.round_ids(competition_id).find(round_id) + 1
	LeagueCupTie.install_round(competition_id, round_id, position, pairs, rule, "uefa")
	season.save.set_status("in_progress")
	return true


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
