extends GdToolsTest

## The German pair in one save (#239): the shipped Bundesliga and 2. Bundesliga
## snapshots start a season at their own 18-club, 34-matchday shape, on the real
## 2026-27 calendar or a generated one, and share the clock.

var SAVE_DIR := TestScratch.dir("saves_test_german_season")
var CACHE_DIR := TestScratch.dir("cache_test_german_season")

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
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
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return
	for name in DirAccess.get_files_at(SAVE_DIR):
		if name.ends_with(".sqlite"):
			DirAccess.remove_absolute(SAVE_DIR.path_join(name))

func test_the_german_pair_starts_on_the_real_calendar() -> void:
	var season := LeagueSeason.create("German Pair", "real", "fixture_days", 4242, ["BL", "BL2"])
	assert_not_null(season, "the German pair season was not created")
	assert_eq(season.save.competition_ids(), ["BL", "BL2"], "the save lost a German tier")
	var state := season.state()
	assert_eq(int(state["total"]), 612, "the German pair is not two full calendars")
	assert_eq((state["competitions"] as Array).size(), 2, "the state lists one German tier")
	assert_eq((state["tables"] as Dictionary)["BL"].size(), 18, "the Bundesliga table is short")
	assert_eq((state["tables"] as Dictionary)["BL2"].size(), 18, "the 2. Bundesliga table is short")
	var per_comp := {"BL": 0, "BL2": 0}
	for fx in season.record.fixtures.all():
		var cid := str(fx["competition_id"])
		per_comp[cid] = int(per_comp.get(cid, 0)) + 1
	assert_eq(int(per_comp["BL"]), 306, "the Bundesliga calendar is short")
	assert_eq(int(per_comp["BL2"]), 306, "the 2. Bundesliga calendar is short")
	var ids := {}
	for fx in season.record.fixtures.all():
		assert_false(ids.has(str(fx["id"])), "two fixtures share an id across the German tiers")
		ids[str(fx["id"])] = true
	assert_eq(int(season.rules_by["BL"]["matchdays"]), 34, "the Bundesliga matchday count is wrong")
	assert_eq(int(season.rules_by["BL2"]["matchdays"]), 34, "the 2.BL matchday count is wrong")
	assert_eq(int(season.rules_by["BL"]["relegation_places"]), 2, "the Bundesliga drop is wrong")
	assert_eq(int(season.rules_by["BL2"]["relegation_places"]), 2, "the 2.BL drop is wrong")
	assert_eq(int(LeagueRules.template("BL2")["promotion_places"]), 2, "2.BL promotion is wrong")
	season.close()

func test_a_generated_german_calendar_is_the_same_shape() -> void:
	var season := LeagueSeason.create("German Generated", "generated", "fixture_days", 77, ["BL"])
	assert_not_null(season, "the generated Bundesliga season was not created")
	var state := season.state()
	assert_eq(int(state["total"]), 306, "the generated Bundesliga calendar is short")
	assert_eq((state["tables"] as Dictionary)["BL"].size(), 18, "the generated table is short")
	var days := {}
	for fx in season.record.fixtures.all():
		days[str(fx["matchday"])] = true
	assert_eq(days.size(), 34, "the generated calendar is not 34 matchdays")
	season.close()

func test_continue_plays_a_german_matchday() -> void:
	var season := LeagueSeason.create("German Continue", "real", "fixture_days", 9, ["BL", "BL2"])
	assert_not_null(season, "the German continue season was not created")
	var before := season.state()
	var seen := {}
	for i in range(30):
		var result := season.advance()
		for report in result["played"]:
			seen[str((report["fixture"] as Dictionary)["competition_id"])] = true
		if seen.has("BL") and seen.has("BL2"):
			break
	assert_true(seen.has("BL"), "Continue never played a Bundesliga fixture")
	assert_true(seen.has("BL2"), "Continue never played a 2. Bundesliga fixture")
	var after := season.state()
	assert_gte(int(after["played"]), int(before["played"]) + 2, "the German ledger lost its first fixtures")
	for cid in ["BL", "BL2"]:
		var total := 0
		for row in (after["tables"] as Dictionary)[cid]:
			total += int(row["points"])
		assert_gte(total, 2, "%s paid no points" % cid)
	season.close()
