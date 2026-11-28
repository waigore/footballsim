extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_league_europe")
var CACHE_DIR := TestScratch.dir("cache_test_league_europe")
const SEED := 5150

var season: LeagueSeason = null


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = _boot()


func after_all() -> void:
	if season != null:
		season.close()
		season = null
	LeagueSeason.active = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)


func _boot() -> LeagueSeason:
	return LeagueSeason.create("Europe Season", "generated", "fixture_days", SEED,
		["PL"], false, [], true)


func _advance_until(round_id: String, competition_id: String = "UCL", cap: int = 200) -> void:
	var guard := 0
	while guard < cap and not LeagueUefa.has_stage(competition_id, round_id):
		season.advance()
		guard += 1


func _advance_complete(cap: int = 500) -> void:
	var guard := 0
	while guard < cap:
		var result: Dictionary = season.advance()
		if bool(result.get("complete", false)):
			break
		guard += 1


func test_a_domestic_save_has_no_continental_state() -> void:
	var domestic := LeagueSeason.create("Domestic Only", "generated", "fixture_days", SEED + 1,
		["PL"], false, [], false)
	var hub := LeagueEurope.hub(domestic.save)
	assert_false(bool(hub["on"]), "a domestic save claims a Europe hub")
	assert_true((hub["cards"] as Array).is_empty(), "a domestic save has continental cards")
	domestic.close()
	season = _boot()


func test_the_hub_carries_three_competition_cards() -> void:
	var hub := LeagueEurope.hub(season.save)
	assert_true(bool(hub["on"]), "the hub is off in a save that runs Europe")
	var cards: Array = hub["cards"]
	assert_eq(cards.size(), 3, "the hub does not carry three competitions")
	for card in cards:
		var row: Dictionary = card
		assert_true(str(row["stage_label"]) != "", "%s has no stage" % row["id"])
		assert_gte(int(row["alive"]), 2, "%s has no clubs still in" % row["id"])
		assert_true(str(row["next"]) != "", "%s has no next night" % row["id"])


func test_the_first_qualifying_round_draws_two_legged_ties() -> void:
	var first := LeagueUefa.first_round("UCL")
	var ties := LeagueEuropeTies.ties("UCL", first)
	assert_gte(ties.size(), 2, "the UCL first round has no ties")
	for row in ties:
		var tie: Dictionary = row
		assert_true(str(tie["home_name"]) != "", "a tie has no home club name")
		assert_true(str(tie["away_name"]) != "", "a tie has no away club name")
		assert_eq((tie["leg_lines"] as Array).size(), 2, "a tie does not have two legs")
		assert_false(bool(tie["played"]), "an unplayed tie claims a result")


func test_a_continental_tie_settles_through_the_watch_path() -> void:
	var first := LeagueUefa.first_round("UCL")
	var rows := PLDatabase.rows(
		"SELECT * FROM league_fixture WHERE competition_id = 'UCL' AND stage = ? "
		+ "ORDER BY id LIMIT 2;", [first])
	assert_eq(rows.size(), 2, "the first round has no first tie")
	var leg1: Dictionary = rows[0]
	var leg2: Dictionary = rows[1]
	assert_eq(int(leg1["leg"]), 1, "the first fixture is not a first leg")
	assert_true(season.set_watch(str(leg1["id"]), true), "a continental fixture refused a watch")
	assert_true(season.set_watch(str(leg1["id"]), false), "a continental fixture kept a watch")
	LeagueCupTie.record_engine(season, leg1, 2, 0)
	var tie := LeagueCupTie.one("UCL", first, 0)
	assert_eq(str(tie.get("winner_club_id", "")), "", "a first leg decided the tie")
	assert_eq(int(tie.get("home_goals", 0)) + int(tie.get("away_goals", 0)), 2,
		"the first leg did not reach the aggregate")
	LeagueCupTie.record_engine(season, leg2, 1, 0)
	assert_true(str(LeagueCupTie.one("UCL", first, 0).get("winner_club_id", "")) != "",
		"the second leg did not decide the tie")


func test_the_rail_names_every_round_and_marks_the_open_one() -> void:
	var rounds := LeagueEuropeTies.rounds("UCL")
	assert_eq(rounds.size(), LeagueUefa.round_ids("UCL").size(), "the rail lost a round")
	var open := LeagueEurope.stage_of("UCL")
	var marked := 0
	for row in rounds:
		var entry: Dictionary = row
		assert_true(str(entry["label"]) != "", "a rail chip has no label")
		if str(entry["id"]) == open:
			assert_eq(str(entry["state"]), "live", "the open round is not marked live")
			marked += 1
	assert_eq(marked, 1, "the rail has no single open round")


func test_a_lost_qualifier_carries_the_drop_badge() -> void:
	var first := LeagueUefa.first_round("UCL")
	_advance_until(LeagueUefa.after("UCL", first))
	var badges := 0
	for row in LeagueEuropeTies.ties("UCL", first):
		var tie: Dictionary = row
		if str(tie["drop"]) != "":
			badges += 1
			assert_true(str(tie["drop"]).begins_with("↓"), "a drop badge does not point down")
	assert_gte(badges, 1, "no loser carries a drop badge")


func test_a_received_loser_carries_the_arrival_badge() -> void:
	var guard := 0
	var arrived := ""
	while guard < 160 and arrived == "":
		for round_id in ["Q2CH", "Q2MP"]:
			for row in LeagueEuropeTies.ties("UECL", round_id):
				if str((row as Dictionary)["arrived"]) != "":
					arrived = str((row as Dictionary)["arrived"])
					break
		if arrived != "":
			break
		season.advance()
		guard += 1
	assert_true(arrived.begins_with("←"), "a club arrived without pointing back")
	assert_true(arrived.contains("UCL") or arrived.contains("UEL"),
		"an arrival badge names no source competition")


func test_the_league_phase_table_bands_its_places() -> void:
	_advance_until(LeagueUefa.LEAGUE_STAGE)
	var rows := LeagueEurope.table("UCL")
	assert_eq(rows.size(), 36, "the UCL league phase is not 36 clubs")
	assert_eq(str((rows[0] as Dictionary)["zone"]), "r16", "the first place is not a last-16 place")
	assert_eq(str((rows[7] as Dictionary)["zone"]), "r16", "the eighth place is not a last-16 place")
	assert_eq(str((rows[8] as Dictionary)["zone"]), "kopo", "the ninth place is not a play-off place")
	assert_eq(str((rows[23] as Dictionary)["zone"]), "kopo", "the 24th place is not a play-off place")
	assert_eq(str((rows[24] as Dictionary)["zone"]), "out", "the 25th place is not eliminated")


func test_playing_a_league_phase_night_moves_the_table() -> void:
	_advance_until(LeagueUefa.LEAGUE_STAGE)
	var guard := 0
	while guard < 20 and not _has_a_result("UCL"):
		season.advance()
		guard += 1
	assert_true(_has_a_result("UCL"), "no league-phase result was ever recorded")


func _has_a_result(competition_id: String) -> bool:
	var row := PLDatabase.row(
		"SELECT COUNT(*) AS n FROM league_fixture WHERE competition_id = ? AND stage = ? "
		+ "AND status = 'played';", [competition_id, LeagueUefa.LEAGUE_STAGE])
	return int(row.get("n", 0)) > 0


func test_the_card_reads_the_league_phase_and_its_matchday() -> void:
	var card := LeagueEurope.card(season.save, "UCL")
	assert_eq(str(card["stage"]), LeagueUefa.LEAGUE_STAGE, "the card left the league phase")
	assert_true(str(card["stage_label"]).begins_with("LEAGUE PHASE"),
		"the card does not read the phase")
	assert_true(str(card["stage_label"]).contains("MD"), "the card loses the matchday")
	assert_eq(int(card["alive"]), 36, "the card does not count 36 clubs")


func test_a_full_season_crowns_three_continental_winners() -> void:
	_advance_complete()
	var honours := LeagueEurope.honours(season.save)
	assert_eq(honours.size(), 3, "the podium does not carry three continental honours")
	for row in honours:
		var honour: Dictionary = row
		assert_true(str(honour["winner_name"]) != "", "%s has no winner" % honour["id"])
		assert_true(str(honour["runner_up_name"]) != "", "%s has no runner-up" % honour["id"])
		assert_true(str(honour["score_line"]) != "", "%s has no final score" % honour["id"])
		assert_eq(LeagueEurope.stage_label(str(honour["id"])), "COMPLETE",
			"%s does not read complete" % honour["id"])
	var summary := season.summary()
	assert_eq((summary.get("uefa", []) as Array).size(), 3,
		"the season summary loses the continental honours")
