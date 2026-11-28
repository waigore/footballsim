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


func _season(name: String, cups: bool = true) -> LeagueSeason:
	return LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"], cups, [], true)


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


func _positions(season: LeagueSeason) -> Array:
	var out: Array = []
	for row in season.record.standings.table():
		if str(row.get("competition_id", "")) == "PL":
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


func _fallback_names(result: Dictionary, reason: String) -> bool:
	for row in (result.get("pools", {}) as Dictionary).get("fallback", []):
		if str((row as Dictionary).get("reason", "")) == reason:
			return true
	return false


func test_the_pools_refill_and_cascade_across_two_seasons() -> void:
	var season := _season("Pools League")
	assert_not_null(season, "the season did not boot")
	var before := _shape()
	var table := _positions(season)
	_cup_winner("FAC", str(table[11]), str(table[0]))
	_finish(season)
	var first := SeasonRollover.apply(season)
	assert_true(bool(first.get("ok", false)), "the rollover refused: %s" % str(first))
	var after := _shape()
	for key in before.keys():
		assert_eq(int(after.get(key, -1)), int(before[key]), "the shape drifted at %s" % key)
	var ucl := _real_clubs("UCL", "LP", "ENG")
	assert_eq(ucl.size(), 5, "England lost its Champions League places")
	for i in range(4):
		assert_true(ucl.has(str(table[i])), "%s finished %s but missed the league phase"
			% [table[i], i + 1])
	var uecl := _real_clubs("UECL", "POMP", "ENG")
	assert_eq(uecl.size(), 1, "England lost its Conference League place")
	assert_eq(uecl[0], str(table[11]), "the cup winner did not take the lowest place")
	assert_true((first.get("pools", {}).get("carried", []) as Array).has("ESP"),
		"the carried association is not recorded")
	assert_true(LeagueUefaPools.note(season.save).contains("ESP CARRIED OVER"),
		"the hub does not name the carried association")
	var second_table := _positions(season)
	_cup_winner("FAC", str(second_table[0]), str(second_table[1]))
	_finish(season)
	var second := SeasonRollover.apply(season)
	var cascade := _real_clubs("UECL", "POMP", "ENG")
	assert_eq(cascade[0], str(second_table[8]), "the place did not pass to the next league place")
	assert_true(_fallback_names(second, "cup_winner_higher"), "the passed-down place is not named")
	season.close()


func test_the_band_is_stored_frozen_and_falls_back() -> void:
	var season := _season("Pools Bands")
	var save := season.save
	assert_false(LeagueUefaBands.store(save).is_empty(), "the bands were not stored")
	var club := str(LeagueUefa.entrants("UCL", "LP")[0])
	var band := LeagueUefaBands.band(save, "UCL", club)
	assert_gte(band, 1, "a stored band is outside the pots")
	PLDatabase.execute("UPDATE player SET ovr = 99 WHERE club_id = ?;", [club])
	StrongestXI.apply_all()
	assert_eq(LeagueUefaBands.band(save, "UCL", club), band, "a squad change moved a frozen band")
	assert_eq(LeagueUefaBands.pots(save, "UCL", LeagueUefa.entrants("UCL", "LP")).size(), 4,
		"the league phase lost a pot")
	var stored := LeagueUefaBands.bands_of(save, "UCL")
	var outside := ""
	for club_id in PLRepository.shared().club_ids("PL"):
		if not stored.has(str(club_id)):
			outside = str(club_id)
			break
	assert_true(outside != "", "every English club already holds a band")
	var peers: Array = []
	for club_id in LeagueUefa.entrants("UCL", "LP"):
		if LeagueUefa.association_of(str(club_id)) == "ENG" and stored.has(str(club_id)):
			peers.append(int(stored[str(club_id)]))
	peers.sort()
	assert_eq(LeagueUefaBands.band(save, "UCL", outside), int(peers[peers.size() / 2]),
		"an unbanded club did not take its association's median band")
	assert_eq(LeagueUefaBands.band(save, "UCL", "no-such-club"), 3,
		"an unknown club did not take the middle pot")
	season.close()


func test_a_cup_off_league_names_the_fallback() -> void:
	var season := _season("Pools No Cup", false)
	var table := _positions(season)
	_finish(season)
	var result := SeasonRollover.apply(season)
	var uecl := _real_clubs("UECL", "POMP", "ENG")
	assert_eq(uecl[0], str(table[8]), "a cup-off association did not fall back to the league")
	assert_true(_fallback_names(result, "cup_off"), "the cup-off fallback is not named")
	season.close()



func test_the_europe_hub_paints_the_entrants_reading() -> void:
	var view := {"cards": [], "entrants": "ENTRANTS: ESP CARRIED OVER", "touch": false}
	var items := LeagueEuropeSheet.new().layout(Vector2(900.0, 600.0), view)
	var found := false
	for item in items:
		if str(item.get("kind", "")) == "note" \
				and str(item.get("label", "")) == "ENTRANTS: ESP CARRIED OVER":
			found = true
	assert_true(found, "the hub does not paint the entrants reading")
