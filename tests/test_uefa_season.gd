extends GdToolsTest


const SEED := 424242


func _season() -> LeagueSeason:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	return LeagueSeason.create("UEFA Path", "generated", "fixture_days", SEED, ["PL"], false, [], true)


func _advance_to_complete(season: LeagueSeason, cap: int = 400) -> int:
	var guard := 0
	while guard < cap:
		var result := season.advance()
		if bool(result.get("complete", false)):
			break
		guard += 1
	return guard


func test_the_three_competitions_boot_on_the_shared_clock() -> void:
	var season := _season()
	assert_true(season != null, "the season did not boot")
	for cid in LeagueUefa.IDS:
		var staged := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = ?;", [cid])
		assert_gte(int(staged.get("n", 0)), 2, "%s has no fixtures on the clock" % cid)
	season.close()


func test_the_qualifying_path_opens_at_the_first_round() -> void:
	var season := _season()
	for cid in LeagueUefa.IDS:
		var first := LeagueUefa.first_round(cid)
		assert_true(LeagueUefa.has_stage(cid, first), "%s did not draw %s" % [cid, first])
		var ties := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM cup_tie WHERE competition_id = ? AND round_id = ?;",
			[cid, first])
		assert_gte(int(ties.get("n", 0)), 1, "%s %s has no ties" % [cid, first])
	season.close()


func test_the_league_phase_is_thirty_six_clubs() -> void:
	var season := _season()
	var guard := 0
	while guard < 60 and not LeagueUefa.has_stage("UCL", LeagueUefa.LEAGUE_STAGE):
		season.advance()
		guard += 1
	assert_true(LeagueUefa.has_stage("UCL", LeagueUefa.LEAGUE_STAGE),
		"the UCL league phase never opened")
	for cid in LeagueUefa.IDS:
		var row := PLDatabase.row(
			"SELECT COUNT(DISTINCT club_id) AS n FROM league_table WHERE competition_id = ?;",
			[cid])
		assert_eq(int(row.get("n", 0)), 36, "%s league phase is not 36 clubs" % cid)
		var matches := LeagueUefa.league_matches(cid)
		var per_club := {}
		for club_row in PLDatabase.rows(
				"SELECT home_club_id AS club_id FROM league_fixture WHERE competition_id = ? "
				+ "AND stage = ? UNION ALL SELECT away_club_id AS club_id FROM league_fixture "
				+ "WHERE competition_id = ? AND stage = ?;",
				[cid, LeagueUefa.LEAGUE_STAGE, cid, LeagueUefa.LEAGUE_STAGE]):
			var key := str(club_row["club_id"])
			per_club[key] = int(per_club.get(key, 0)) + 1
		for club_id in per_club.keys():
			assert_eq(int(per_club[club_id]), matches,
				"%s: %s plays %s matches" % [cid, club_id, per_club[club_id]])
	season.close()


func test_a_full_season_crowns_three_winners() -> void:
	var season := _season()
	_advance_to_complete(season)
	for cid in LeagueUefa.IDS:
		var final := PLDatabase.row(
			"SELECT winner_club_id FROM cup_tie WHERE competition_id = ? AND round_id = 'F' "
			+ "AND winner_club_id <> '';", [cid])
		assert_false(final.is_empty(), "%s has no champion" % cid)
		assert_false(str(final.get("winner_club_id", "")) == "",
			"%s final has no winner" % cid)
	season.close()


func test_the_draw_is_deterministic_from_the_seed() -> void:
	var first := _season()
	var before := _fixtures_of("UCL")
	first.close()
	var second := _season()
	var after := _fixtures_of("UCL")
	assert_eq(before, after, "the same seed drew a different UCL")
	second.close()


func _fixtures_of(competition_id: String) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT id, home_club_id, away_club_id FROM league_fixture "
			+ "WHERE competition_id = ? ORDER BY id;", [competition_id]):
		out.append("%s:%s-%s" % [row["id"], row["home_club_id"], row["away_club_id"]])
	return out


func test_a_lost_tie_drops_into_the_competition_below() -> void:
	var season := _season()
	var guard := 0
	while guard < 40 and not LeagueUefa.has_stage("UEL", "Q3CH"):
		season.advance()
		guard += 1
	var dropped := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM competition_member WHERE role LIKE 'drop:%';")
	assert_gte(int(dropped.get("n", 0)), 1, "no club dropped between competitions")
	var into_uel := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM competition_member WHERE competition_id = 'UEL' "
		+ "AND role LIKE 'drop:%';")
	assert_gte(int(into_uel.get("n", 0)), 1, "nothing dropped from the UCL into the UEL")
	season.close()
