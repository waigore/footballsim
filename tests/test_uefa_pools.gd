extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_uefa_pools_481")
var CACHE_DIR := TestScratch.dir("cache_uefa_pools_481")
const SEED := 481481


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _season(name: String, comps: Array = ["PL"], cups: bool = true) -> LeagueSeason:
	return LeagueSeason.create(name, "generated", "fixture_days", SEED, comps, cups, [], true)


func _finish(season: LeagueSeason) -> void:
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		var hg := 3 if home < away else 1
		var ag := 1 if home < away else 3
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [hg, ag, str(row["id"])])
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	SeasonSettle.apply(season)


func _positions(season: LeagueSeason, competition_id: String) -> Array:
	var out: Array = []
	for row in season.record.standings.table():
		if str(row.get("competition_id", "")) == competition_id:
			out.append(str(row["club_id"]))
	return out


func _real_clubs(competition_id: String, round_id: String, association: String) -> Array:
	var out: Array = []
	for club_id in LeagueUefa.entrants(competition_id, round_id):
		if LeagueUefa.association_of(str(club_id)) == association:
			out.append(str(club_id))
	return out


func _shape() -> Dictionary:
	var out := {}
	for row in PLDatabase.rows(
			"SELECT m.competition_id, m.role, c.country, COUNT(*) AS n FROM competition_member m "
			+ "JOIN club c ON c.id = m.member_id WHERE m.member_kind = 'club' "
			+ "GROUP BY m.competition_id, m.role, c.country;"):
		out["%s|%s|%s" % [row["competition_id"], row["role"], row["country"]]] = int(row["n"])
	return out


func _cup_winner(cup: String, winner: String, other: String) -> void:
	var rounds := LeagueCup.rounds(cup)
	var last := str((rounds[rounds.size() - 1] as Dictionary)["id"])
	PLDatabase.execute(
		"INSERT OR REPLACE INTO cup_tie (competition_id, round_id, tie_index, home_club_id, "
		+ "away_club_id, winner_club_id, home_goals, away_goals, pens_home, pens_away, "
		+ "extra_time, season_index) VALUES (?, ?, 0, ?, ?, ?, 2, 0, -1, -1, 0, ?);",
		[cup, last, winner, other, winner, 0])


func _rollover(season: LeagueSeason) -> Dictionary:
	return SeasonRollover.apply(season)


func test_the_access_list_shape_survives_the_rollover() -> void:
	var season := _season("Pools Shape")
	assert_not_null(season, "the season did not boot")
	var before := _shape()
	_finish(season)
	var result := _rollover(season)
	assert_true(bool(result.get("ok", false)), "the rollover refused: %s" % str(result))
	var after := _shape()
	for key in before.keys():
		assert_eq(int(after.get(key, -1)), int(before[key]), "the shape drifted at %s" % key)
	season.close()


func test_the_league_places_fill_the_next_season() -> void:
	var season := _season("Pools Places")
	var top := _positions(season, "PL")
	_finish(season)
	_rollover(season)
	var clubs := _real_clubs("UCL", "LP", "ENG")
	assert_eq(clubs.size(), 5, "England lost its Champions League places")
	for i in range(4):
		assert_true(clubs.has(str(top[i])), "%s finished %s but missed the league phase"
			% [top[i], i + 1])
	season.close()


func test_the_cup_winner_takes_the_association_lowest_place() -> void:
	var season := _season("Pools Cup")
	var table := _positions(season, "PL")
	_cup_winner("FAC", str(table[11]), str(table[0]))
	_finish(season)
	_rollover(season)
	var clubs := _real_clubs("UECL", "POMP", "ENG")
	assert_eq(clubs.size(), 1, "England lost its Conference League place")
	assert_eq(clubs[0], str(table[11]), "the cup winner did not take the lowest place")
	season.close()


func test_a_qualified_cup_winner_passes_the_place_down() -> void:
	var season := _season("Pools Cup Higher")
	var table := _positions(season, "PL")
	_cup_winner("FAC", str(table[0]), str(table[1]))
	_finish(season)
	var result := _rollover(season)
	var clubs := _real_clubs("UECL", "POMP", "ENG")
	assert_eq(clubs.size(), 1, "England lost its Conference League place")
	assert_eq(clubs[0], str(table[8]), "the place did not pass to the next league place")
	var fallback: Array = (result.get("pools", {}) as Dictionary).get("fallback", [])
	var named := false
	for row in fallback:
		if str((row as Dictionary).get("association", "")) == "ENG" \
				and str((row as Dictionary).get("reason", "")) == "cup_winner_higher":
			named = true
	assert_true(named, "the passed-down cup place is not named")
	season.close()


func test_a_cup_off_league_names_the_fallback() -> void:
	var season := _season("Pools No Cup", ["PL"], false)
	var table := _positions(season, "PL")
	_finish(season)
	var result := _rollover(season)
	var clubs := _real_clubs("UECL", "POMP", "ENG")
	assert_eq(clubs[0], str(table[8]), "a cup-off association did not fall back to the league")
	var fallback: Array = (result.get("pools", {}) as Dictionary).get("fallback", [])
	var named := false
	for row in fallback:
		if str((row as Dictionary).get("reason", "")) == "cup_off":
			named = true
	assert_true(named, "the cup-off fallback is not named")
	season.close()


func test_an_inactive_association_is_carried_over() -> void:
	var season := _season("Pools Carried")
	var before := _real_clubs("UCL", "LP", "ESP")
	_finish(season)
	var result := _rollover(season)
	var after := _real_clubs("UCL", "LP", "ESP")
	assert_eq(before, after, "Spain's entrants moved without a league to move them")
	assert_true((result.get("pools", {}).get("carried", []) as Array).has("ESP"),
		"the carried association is not recorded")
	assert_true(LeagueUefaPools.note(season.save).contains("ESP CARRIED OVER"),
		"the hub does not name the carried association")
	season.close()


func test_the_band_store_is_frozen_at_boot() -> void:
	var season := _season("Pools Bands")
	var save := season.save
	assert_false(LeagueUefaBands.store(save).is_empty(), "the bands were not stored")
	var club := str(LeagueUefa.entrants("UCL", "LP")[0])
	var band := LeagueUefaBands.band(save, "UCL", club)
	assert_gte(band, 1, "a stored band is outside the pots")
	PLDatabase.execute("UPDATE player SET ovr = 99 WHERE club_id = ?;", [club])
	StrongestXI.apply_all()
	assert_eq(LeagueUefaBands.band(save, "UCL", club), band,
		"a squad change moved a frozen band")
	var pots := LeagueUefaBands.pots(save, "UCL", LeagueUefa.entrants("UCL", "LP"))
	assert_eq(pots.size(), 4, "the league phase lost a pot")
	season.close()


func test_an_unbanded_club_reads_the_median_or_the_middle_pot() -> void:
	var season := _season("Pools Fallback")
	var save := season.save
	var outside := ""
	for club_id in PLRepository.shared().club_ids("PL"):
		if not LeagueUefa.entrants("UCL", "LP").has(str(club_id)):
			outside = str(club_id)
			break
	assert_true(outside != "", "every English club already holds a band")
	var peers: Array = []
	var stored := LeagueUefaBands.bands_of(save, "UCL")
	for club_id in LeagueUefa.entrants("UCL", "LP"):
		if LeagueUefa.association_of(str(club_id)) == "ENG" and stored.has(str(club_id)):
			peers.append(int(stored[str(club_id)]))
	peers.sort()
	assert_eq(LeagueUefaBands.band(save, "UCL", outside), int(peers[peers.size() / 2]),
		"an unbanded club did not take its association's median band")
	assert_eq(LeagueUefaBands.band(save, "UCL", "no-such-club"), 3,
		"an unknown club did not take the middle pot")
	season.close()


func test_the_europe_hub_names_the_season_two_pools() -> void:
	var view := {"cards": [], "entrants": "ENTRANTS: ESP CARRIED OVER", "touch": false}
	var items := LeagueEuropeSheet.new().layout(Vector2(900.0, 600.0), view)
	var found := false
	for item in items:
		if str(item.get("kind", "")) == "note" \
				and str(item.get("label", "")) == "ENTRANTS: ESP CARRIED OVER":
			found = true
	assert_true(found, "the hub does not paint the entrants reading")
