class_name LeagueSeasonSim
extends RefCounted


static func fixture(season: LeagueSeason, fx: Dictionary) -> Dictionary:
	var fixture_id := str(fx["id"])
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var cid := str(fx.get("competition_id", ""))
	var seed := seed_for(season, fixture_id)
	var model := PoissonModel.new(seed, home, away)
	var score := model.sample()
	var hxi := StrongestXI.pick(TeamData.get_team(home))
	var axi := StrongestXI.pick(TeamData.get_team(away))
	var events: Array = []
	events.append_array(MatchEvents.side(seed + 11, fixture_id, home, hxi, score.x))
	events.append_array(MatchEvents.side(seed + 23, fixture_id, away, axi, score.y))
	season.record.report.save_result(fixture_id, score.x, score.y, home, away,
		season.record.standings, cid)
	season.record.report.add_events(events)
	LeagueSettle.auto(season.record, fixture_id, home, away, hxi, axi, events, seed,
		str(fx["kickoff"]), int(fx["matchday"]))
	LeagueHighlights.store_auto(season.record, int(season.rng.seed), fixture_id, events, home, away)


	PLRepository.shared().invalidate()
	return season.report(fixture_id)


static func seed_for(season: LeagueSeason, fixture_id: String) -> int:
	var h := 0
	for i in range(fixture_id.length()):
		h = int((h * 31 + fixture_id.unicode_at(i)) % 2147483647)
	return int(season.rng.seed) + h
