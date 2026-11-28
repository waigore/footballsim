class_name LeagueSeasonSim
extends RefCounted


static func fixture(season: LeagueSeason, fx: Dictionary) -> Dictionary:
	var fixture_id := str(fx["id"])
	var seed := seed_for(season, fixture_id)
	if LeagueUefa.is_continental(str(fx.get("competition_id", ""))):
		return _uefa_fixture(season, fx, seed)
	if LeagueCup.is_cup_fixture(fx):
		return _cup_fixture(season, fx, seed)
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var score := PoissonModel.new(seed, home, away).sample()
	_record(season, fx, score, seed)
	PLRepository.shared().invalidate()
	return season.report(fixture_id)


static func _cup_fixture(season: LeagueSeason, fx: Dictionary, seed: int) -> Dictionary:
	var fixture_id := str(fx["id"])
	var sim := LeagueCupTie.simulate(season, fx)
	if sim.is_empty():
		return {}
	var score: Vector2i = sim["score"]
	_record(season, fx, score, seed)
	LeagueCupState.after_played(season, fx)
	PLRepository.shared().invalidate()
	return season.report(fixture_id)


static func _uefa_fixture(season: LeagueSeason, fx: Dictionary, seed: int) -> Dictionary:
	var fixture_id := str(fx["id"])
	var stage := str(fx.get("stage", ""))
	var score := Vector2i.ZERO
	if stage == LeagueUefa.LEAGUE_STAGE:
		score = PoissonModel.new(seed, str(fx["home_club_id"]), str(fx["away_club_id"])).sample()
		_record_league(season, fx, score, seed)
	else:
		var sim := LeagueCupTie.simulate(season, fx)
		if sim.is_empty():
			return {}
		score = sim["score"]
		_record_league(season, fx, score, seed)
	LeagueUefaState.after_played(season, fx)
	PLRepository.shared().invalidate()
	return season.report(fixture_id)


static func _record_league(season: LeagueSeason, fx: Dictionary, score: Vector2i,
		seed: int) -> void:
	var fixture_id := str(fx["id"])
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var cid := str(fx.get("competition_id", ""))
	var stage := str(fx.get("stage", ""))
	var hxi := StrongestXI.pick(TeamData.get_team(home), cid)
	var axi := StrongestXI.pick(TeamData.get_team(away), cid)
	var events := _events(fx, score, seed)
	var table: LeagueStandings = null
	if stage == LeagueUefa.LEAGUE_STAGE:
		table = season.record.standings
	season.record.report.save_result(fixture_id, score.x, score.y, home, away,
		table, cid)
	season.record.report.add_events(events)
	LeagueSettle.auto(season.record, fixture_id, home, away, hxi, axi, events, seed,
		str(fx["kickoff"]), int(fx["matchday"]), cid)
	LeagueHighlights.store_auto(season.record, int(season.rng.seed), fixture_id, events,
		home, away)


static func _record(season: LeagueSeason, fx: Dictionary, score: Vector2i, seed: int) -> void:
	var fixture_id := str(fx["id"])
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var cid := str(fx.get("competition_id", ""))
	if LeagueCup.is_cup(cid):
		season.record.report.save_result(fixture_id, score.x, score.y, home, away, null, cid)
		var cup_events := _events(fx, score, seed)
		season.record.report.add_events(cup_events)
		LeagueHighlights.store_auto(season.record, int(season.rng.seed), fixture_id, cup_events,
			home, away)
		return
	var hxi := StrongestXI.pick(TeamData.get_team(home), cid)
	var axi := StrongestXI.pick(TeamData.get_team(away), cid)
	var events := _events(fx, score, seed)
	season.record.report.save_result(fixture_id, score.x, score.y, home, away,
		season.record.standings, cid)
	season.record.report.add_events(events)
	LeagueSettle.auto(season.record, fixture_id, home, away, hxi, axi, events, seed,
		str(fx["kickoff"]), int(fx["matchday"]), cid)
	LeagueHighlights.store_auto(season.record, int(season.rng.seed), fixture_id, events, home, away)


static func _events(fx: Dictionary, score: Vector2i, seed: int) -> Array:
	var fixture_id := str(fx["id"])
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var cid := str(fx.get("competition_id", ""))
	var hxi := StrongestXI.pick(TeamData.get_team(home), cid)
	var axi := StrongestXI.pick(TeamData.get_team(away), cid)
	var events: Array = []
	events.append_array(MatchEvents.side(seed + 11, fixture_id, home, hxi, score.x))
	events.append_array(MatchEvents.side(seed + 23, fixture_id, away, axi, score.y))
	return events


static func seed_for(season: LeagueSeason, fixture_id: String) -> int:
	var h := 0
	for i in range(fixture_id.length()):
		h = int((h * 31 + fixture_id.unicode_at(i)) % 2147483647)
	return int(season.rng.seed) + h
