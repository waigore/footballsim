extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_german_relegation")
var CACHE_DIR := TestScratch.dir("cache_test_german_relegation")
const SEED := 5150
const PRISTINE := "_pristine.sqlite"

var season: LeagueSeason = null
var slug := ""
var expected_tie: Dictionary = {}

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("German Relegation", "generated", "fixture_days", SEED,
		["BL", "BL2"])
	assert_not_null(season, "the German season was not created")
	slug = season.save.slug
	_finish_open_season(season)
	expected_tie = LeagueRelegation.build(season)
	_snapshot_as(PRISTINE)

func after_all() -> void:
	if season != null:
		season.close()
		season = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	for name in DirAccess.get_files_at(SAVE_DIR):
		if name.ends_with(".sqlite"):
			DirAccess.remove_absolute(SAVE_DIR.path_join(name))


func _finish_open_season(built: LeagueSeason) -> void:
	var scored := {}
	for i in range(18):
		scored[i] = 40 - i * 2
	var rows := PLDatabase.rows(
		"SELECT id, home_club_id, away_club_id, competition_id FROM league_fixture;")
	for row in rows:
		var comp := str(row["competition_id"])
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		var table := built.record.standings.table(comp)
		var home_place := _place(table, home, scored, comp)
		var away_place := _place(table, away, scored, comp)
		var hg := 2 if home_place < away_place else 0
		var ag := 2 if away_place < home_place else 0
		PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = ?, "
			+ "away_goals = ? WHERE id = ?;", [hg, ag, str(row["id"])])
	built.record.standings.recompute()
	if built.record.fixtures.unplayed() == 0:
		built.save.set_status("complete")


func _snapshot_as(name: String) -> void:
	if season == null or season.save == null:
		return
	season.save.ensure_open()
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(season.save.path)
	var out := FileAccess.open(SAVE_DIR.path_join(name), FileAccess.WRITE)
	if out != null and not bytes.is_empty():
		out.store_buffer(bytes)
		out.close()
	season.save.ensure_open()


func _restore(name: String) -> LeagueSeason:
	if season != null:
		season.close()
		season = null
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(SAVE_DIR.path_join(name))
	var dest := SAVE_DIR.path_join(slug + LeagueSave.EXT)
	var out := FileAccess.open(dest, FileAccess.WRITE)
	assert_true(out != null and not bytes.is_empty(), "the %s German save was missing" % name)
	out.store_buffer(bytes)
	out.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the %s German save did not reopen" % name)
	return season


func _fresh() -> LeagueSeason:
	return _restore(PRISTINE)


func _place(table: Array, club_id: String, scored: Dictionary, comp: String) -> int:
	for i in range(table.size()):
		if str((table[i] as Dictionary)["club_id"]) == club_id:
			return i
	return 99

func test_the_tie_is_the_sixteenth_against_the_third() -> void:
	var current := _fresh()
	assert_eq(current.record.fixtures.unplayed(), 0, "the season is not played out")
	var tie := LeagueRelegation.build(current)
	assert_false(tie.is_empty(), "a finished German pair has no Relegation")
	assert_true(str(tie["top_club_id"]).begins_with("BL-"), "the tie is not the top-flight club")
	assert_true(str(tie["second_club_id"]).begins_with("BL2-"),
		"the tie is not the second-tier club")
	assert_eq(int(tie["top_position"]), 16, "the Relegation is not the sixteenth place")
	assert_eq(int(tie["second_position"]), 3, "the Relegation is not the third place")
	var legs: Array = tie["legs"]
	assert_eq(legs.size(), 2, "the Relegation is not two legs")
	assert_eq(str(legs[0]["home"]), str(tie["top_club_id"]),
		"the first leg is not at the top-flight club")
	assert_eq(str(legs[1]["home"]), str(tie["second_club_id"]),
		"the second leg is not at the second-tier club")
	assert_true(str(tie["winner_club_id"]) != "", "the tie named no winner")
	assert_true(str(tie["text"]).contains("—"), "the tie has no reading")

func test_the_same_seed_settles_the_same_tie() -> void:
	var again := _fresh()
	assert_not_null(again, "the finished German season did not reopen")
	var tie := LeagueRelegation.build(again)
	assert_eq(str(tie["top_club_id"]), str(expected_tie["top_club_id"]), "the tie moved between runs")
	assert_eq(tie["legs"], expected_tie["legs"], "the legs differ for one seed")
	assert_eq(str(tie["winner_club_id"]), str(expected_tie["winner_club_id"]),
		"the winner differs for one seed")

func test_a_level_aggregate_goes_to_penalties() -> void:

	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var top := int(LeagueRelegation._shootout(4242, "BL-FCB", "BL2-BSC").x)
	var again := int(LeagueRelegation._shootout(4242, "BL-FCB", "BL2-BSC").x)
	assert_eq(top, again, "the shootout is not deterministic for a seed")
	var pens := LeagueRelegation._shootout(4242, "BL-FCB", "BL2-BSC")
	assert_ne(pens.x, pens.y, "a shootout finished level")

func test_the_movers_are_two_up_and_three_down() -> void:
	var current := _fresh()
	var tie := LeagueRelegation.build(current)
	var movers := LeaguePromotion.movers(current, tie)
	assert_false(movers.is_empty(), "a finished German pair has no movers")
	var up: Array = movers["to_top"]
	var down: Array = movers["to_second"]
	assert_gte(up.size(), 2, "fewer than two clubs go up")
	assert_gte(down.size(), 2, "fewer than two clubs go down")
	for club_id in up:
		assert_true(str(club_id).begins_with("BL"), "%s is not a German club" % club_id)
	for club_id in down:
		assert_true(str(club_id).begins_with("BL"), "%s is not a German club" % club_id)
	var table: Array = current.record.standings.table("BL2")
	assert_true(up.has(str((table[0] as Dictionary)["club_id"])), "the 2.BL winner does not go up")
	assert_true(up.has(str((table[1] as Dictionary)["club_id"])), "2.BL's second does not go up")

func test_the_swap_moves_the_clubs_in_the_save() -> void:
	var current := _fresh()
	var summary := current.summary()
	assert_false(summary.is_empty(), "a finished German pair has no podium")
	var tie: Dictionary = summary.get("relegation", {})
	assert_false(tie.is_empty(), "the podium lost the Relegation")
	var movers: Dictionary = summary.get("promotion", {})
	assert_true(bool(movers.get("applied", false)), "the membership swap was never applied")
	for club_id in movers["to_top"]:
		assert_eq(str(LeagueLedger.competition_of(str(club_id))), "BL",
			"%s did not move up in the save" % club_id)
	for club_id in movers["to_second"]:
		assert_eq(str(LeagueLedger.competition_of(str(club_id))), "BL2",
			"%s did not move down in the save" % club_id)


	assert_eq(current.save.status(), "complete", "the save is not marked complete")
	var again := current.summary()
	assert_false(again.is_empty(), "reopening the podium lost the season")
	assert_eq(str((again["competitions"] as Array)[0]["id"]), "BL",
		"the podium's order changed after the swap")

func test_the_podium_reads_the_german_bands() -> void:
	var current := _fresh()
	var summary := current.summary()
	var sections: Array = summary["competitions"]
	assert_eq(sections.size(), 2, "the podium is not one section per German tier")
	var top: Dictionary = sections[0]
	assert_eq(str(top["id"]), "BL", "the podium lost the top tier")
	assert_eq((top["europe"] as Array).size(), 6, "the Bundesliga's Europe band is not six")
	assert_eq((top["relegated"] as Array).size(), 2, "the Bundesliga drops two directly")
	var lower: Dictionary = sections[1]
	assert_eq(str(lower["id"]), "BL2", "the podium lost the second tier")
	assert_eq((lower["europe"] as Array).size(), 0, "the 2. Bundesliga was given a European band")
	assert_eq((lower["relegated"] as Array).size(), 2, "the 2. Bundesliga drops two")
	assert_eq(int((lower["rules"] as Dictionary).get("promotion_places", 0)), 2,
		"the second tier lost its promotion places")

func test_the_table_bands_mark_promotion_and_the_playoff() -> void:
	var bl := LeagueRules.template("BL")
	var bl2 := LeagueRules.template("BL2")
	assert_eq(LeagueRules.zone(1, bl), "ucl", "the Bundesliga champion is not in Europe")
	assert_eq(LeagueRules.zone(6, bl), "uecl", "the Bundesliga's sixth is not in Europe")
	assert_eq(LeagueRules.zone(16, bl), "playoff", "the sixteenth place is not the Relegation")
	assert_eq(LeagueRules.zone(17, bl), "relegation", "the seventeenth does not go down")
	assert_eq(LeagueRules.zone(18, bl), "relegation", "the eighteenth does not go down")
	assert_eq(LeagueRules.zone(1, bl2), "promotion", "the 2.BL winner does not go up")
	assert_eq(LeagueRules.zone(2, bl2), "promotion", "the 2.BL runner-up does not go up")
	assert_eq(LeagueRules.zone(3, bl2), "playoff", "the 2.BL third is not the Relegation")
	assert_eq(LeagueRules.zone(17, bl2), "relegation", "the 2.BL seventeenth does not go down")
	assert_eq(LeagueRules.zone(7, bl2), "", "a mid-table 2.BL place wears a band")
	assert_eq(LeagueRules.zone(20, LeagueRules.template("PL")), "relegation",
		"the Premier League's drop is broken by the new bands")
	assert_eq(LeagueRules.zone(16, LeagueRules.template("PL")), "",
		"the Premier League gained a Relegation place")
	assert_eq(LeagueRules.zone_label("promotion"), "UP", "the promotion band has no label")
	assert_eq(LeagueRules.zone_label("playoff"), "PLO", "the playoff band has no label")

func test_the_club_page_follows_the_swapped_membership() -> void:
	var current := _fresh()
	var summary := current.summary()
	var movers: Dictionary = summary["promotion"]
	var up: Array = movers["to_top"]
	var down: Array = movers["to_second"]
	assert_gte(up.size(), 1, "the swap promoted nobody")
	assert_gte(down.size(), 1, "the swap relegated nobody")
	var promoted := WikiModel.page(WikiModel.TEAM, str(up[0]))
	assert_true(_links_league(promoted, "BL"),
		"the promoted club's page does not link the Bundesliga")
	var relegated := WikiModel.page(WikiModel.TEAM, str(down[0]))
	assert_true(_links_league(relegated, "BL2"),
		"the relegated club's page does not link the 2. Bundesliga")

	assert_eq(int(PLCompetitions.clubs("BL")), 18, "the Bundesliga lost or gained a club")
	assert_eq(int(PLCompetitions.clubs("BL2")), 18, "the 2. Bundesliga lost or gained a club")

func _links_league(page: Dictionary, competition_id: String) -> bool:
	for block in page.get("blocks", []):
		for item in block.get("items", []):
			var target: Dictionary = item.get("target", {})
			if str(target.get("page", "")) != WikiModel.LEAGUE:
				continue
			if str(target.get("id", "")) == competition_id:
				return true
	return false

func test_a_tie_between_the_tiers_is_only_for_a_german_pair() -> void:
	assert_false(LeagueRelegation.runs(["BL"]), "a lone tier plays a Relegation")
	assert_false(LeagueRelegation.runs(["PL"]), "England plays a German Relegation")
	assert_true(LeagueRelegation.runs(["BL", "BL2"]), "a German pair skipped the Relegation")

func test_the_tie_is_applied_only_once() -> void:
	var current := _fresh()
	var tie := LeagueRelegation.build(current)
	var movers := LeaguePromotion.movers(current, tie)
	assert_true(LeaguePromotion.apply(current, movers), "the first swap did not apply")
	assert_true(LeaguePromotion.apply(current, movers), "a second swap reported failure")
	var first_top: Array = movers["to_top"].duplicate()
	var still := LeaguePromotion.movers(current, tie)
	for club_id in first_top:
		assert_eq(str(LeagueLedger.competition_of(str(club_id))), "BL",
			"%s moved twice" % club_id)
	assert_eq(int(still["to_top"].size()), first_top.size(), "the movers changed on a re-apply")
