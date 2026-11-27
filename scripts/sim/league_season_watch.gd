class_name LeagueSeasonWatch
extends RefCounted


static func start(season: LeagueSeason, fixture_id: String) -> Dictionary:
	if season == null or season.record == null or fixture_id == "" or season.finishing:
		return {}
	var fx := season.record.fixtures.one(fixture_id)
	if fx.is_empty():
		return {}


	StrongestXI.apply(str(fx["home_club_id"]))
	StrongestXI.apply(str(fx["away_club_id"]))
	season.watching_fixture = fixture_id
	season.captured = []
	return {
		"fixture_id": fixture_id,
		"home": str(fx["home_club_id"]), "away": str(fx["away_club_id"]),
		"competition_id": str(fx.get("competition_id", "")),
		"competition": PLRepository.shared().competition_name(str(fx.get("competition_id", ""))),
	}


static func cancel(season: LeagueSeason) -> void:
	if season == null or season.finishing:
		return
	season.watching_fixture = ""
	season.captured = []
	season.state_changed.emit()


static func capture(season: LeagueSeason, pack: Dictionary) -> void:
	if season == null or season.watching_fixture == "" or pack.is_empty():
		return
	season.captured.append(pack)

static func record_engine(season: LeagueSeason, engine: MatchEngine) -> void:
	if season == null:
		return
	var fixture_id := season.watching_fixture
	if fixture_id == "":
		return
	season.watching_fixture = ""
	season.finishing = false
	var fx := season.record.fixtures.one(fixture_id)
	if fx.is_empty():
		return
	var home := int(engine.score[0])
	var away := int(engine.score[1])
	var cid := str(fx.get("competition_id", ""))
	var events := LeagueHighlights.engine_events(engine, fixture_id)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	season.record.report.save_result(fixture_id, home, away,
		str(fx["home_club_id"]), str(fx["away_club_id"]), season.record.standings, cid)
	season.record.report.add_events(events)
	LeagueSettle.watch(season.record, engine, events, int(season.rng.seed),
		str(fx["kickoff"]), int(fx["matchday"]))
	LeagueHighlights.store_watch(season.record, int(season.rng.seed), fixture_id, season.captured,
		str(fx["home_club_id"]), str(fx["away_club_id"]))
	season.captured = []
	PLDatabase.transaction("COMMIT;")

	PLRepository.shared().invalidate()


	season.state_changed.emit()
	season.match_recorded.emit(season.report(fixture_id))
