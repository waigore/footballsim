extends GdToolsTest

## The club page reads the season ahead (DR-20261124-09): a club's results are
## only the games already played, and the games still to come are their own
## reading — soonest first, from the same ledger (the open season or the
## snapshot), each row pointing at the opponent. One season is shared by the
## suite so the season work is paid once; the last test walks it to the end.

var SAVE_DIR := TestScratch.dir("saves_test_wiki_upcoming")
var CACHE_DIR := TestScratch.dir("cache_test_wiki_upcoming")
const SEED := 2031

var season: LeagueSeason = null
var day_one: Array = []

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Upcoming Season", "generated", "fixture_days", SEED)
	assert_not_null(season, "the season was not created")
	season.advance()
	day_one = season.record.fixtures(1)

func after_all() -> void:
	if season != null:
		season.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

# ---------------------------------------------------------------- season ---

func test_the_club_page_shows_the_season_s_results_and_what_is_next() -> void:
	var club_id := str(day_one[0]["home_club_id"])
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var text := _flatten(page)
	assert_true(text.contains("NEXT FIXTURES  ·  SEASON"), "the club page is missing what comes next")
	var results := _rows_below(page, "RESULTS  ·  SEASON")
	assert_eq(results.size(), 1, "the club one game in lists the wrong number of results")
	var next := _rows_below(page, "NEXT FIXTURES  ·  SEASON")
	assert_gte(next.size(), 1, "the season ahead is empty after one round")
	assert_lte(next.size(), 6, "the page lists more fixtures than it asked for")
	# The result of the day is a result, never a fixture ahead.
	var played_on := FixtureCalendar.day_label(str(day_one[0]["kickoff"]))
	for row in next:
		assert_ne(str(row["cells"][0]), played_on, "the played day is listed as still to come")
		assert_eq((row["cells"] as Array).size(), 3, "a season's fixture ahead lost its gameweek")
		assert_true(str(row["cells"][1]).begins_with("GW "), "a season's fixture ahead has no gameweek")
		assert_true(str(row["cells"][2]).contains(" v "), "a fixture row lost its two clubs")

func test_the_fixtures_ahead_run_soonest_first() -> void:
	var club_id := str(day_one[0]["home_club_id"])
	var rows := WikiModel.repo().upcoming(club_id, 6)
	assert_gte(rows.size(), 2, "a club has no run of fixtures ahead")
	var previous := ""
	for row in rows:
		var date := str(row["kickoff"])
		assert_true(previous == "" or date >= previous, "the fixtures ahead are out of date order")
		assert_ne(str(row["status"]), "played", "a played fixture was listed as still to come")
		previous = date

func test_each_fixture_ahead_opens_the_opponent() -> void:
	var club_id := str(day_one[0]["home_club_id"])
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var rows := _rows_below(page, "NEXT FIXTURES  ·  SEASON")
	assert_gte(rows.size(), 1, "no row to check")
	for row in rows:
		var target: Dictionary = row["target"]
		assert_eq(str(target["page"]), WikiModel.TEAM, "a fixture ahead does not open a club")
		assert_ne(str(target["id"]), club_id, "a fixture ahead opens the club it belongs to")
		assert_true(WikiModel.has_page(str(target["page"]), str(target["id"])), "a fixture ahead is a dead link")

# -------------------------------------------------------------- snapshot ---

func test_without_a_season_the_page_reads_the_snapshot_ahead() -> void:
	season.close()
	PLRepository.shared().invalidate()
	var page := WikiModel.page(WikiModel.TEAM, "MUN")
	var text := _flatten(page)
	assert_true(text.contains("NEXT FIXTURES  ·  SNAPSHOT"), "the snapshot has no schedule ahead")
	var next := _rows_below(page, "NEXT FIXTURES  ·  SNAPSHOT")
	assert_gte(next.size(), 5, "the snapshot's remaining schedule is short")
	var results := _rows_below(page, "RESULTS  ·  SNAPSHOT")
	assert_gte(results.size(), 5, "the snapshot's results block is short")
	# The two readings never share a row shape: a result carries its score, a
	# fixture ahead carries its two clubs and no gameweek (the snapshot has none).
	for row in results:
		assert_true(str(row["cells"][1]).contains(" – "), "a result row lost its score")
	for row in next:
		assert_eq((row["cells"] as Array).size(), 2, "the snapshot's fixture ahead claims a gameweek it has not got")
		assert_false(str(row["cells"][1]).contains(" – "), "a fixture ahead carries a score")
	# Bind the season again so the shared fixture stays valid for the walk.
	season = LeagueSeason.open(LeagueSave.current.slug if LeagueSave.current != null else season.save.slug)
	assert_not_null(season, "the save could not be reopened")

# ------------------------------------------------------------------ data ---

func test_results_and_fixtures_ahead_never_overlap() -> void:
	var played := PLRepository.shared().fixtures("MUN", 100)
	var ahead := PLRepository.shared().upcoming("MUN", 100)
	assert_gte(played.size(), 1, "the snapshot has no played fixture for the club")
	assert_gte(ahead.size(), 1, "the snapshot has no fixture ahead for the club")
	var ids := {}
	for row in played:
		assert_eq(int(row["played"]), 1, "an unplayed fixture was read as a result")
		ids[str(row["id"])] = true
	for row in ahead:
		assert_eq(int(row["played"]), 0, "a result was read as a fixture ahead")
		assert_false(ids.has(str(row["id"])), "a fixture is both played and still to come")
	assert_eq(played.size() + ahead.size(), 38, "a club plays 38 games in the snapshot")

# ------------------------------------------------------------------ end ---

## Declared last on purpose: it finishes the shared season, so every reading
## above has run on a season still in play.
func test_a_finished_season_says_nothing_is_left() -> void:
	var club_id := str(day_one[0]["home_club_id"])
	var guard := 0
	while str(season.state().get("status", "")) != "complete" and guard < 60:
		season.advance()
		guard += 1
	assert_eq(str(season.state().get("status", "")), "complete", "the season never finished")
	assert_eq(WikiModel.repo().upcoming(club_id, 6).size(), 0, "a finished season still has fixtures ahead")
	var text := _flatten(WikiModel.page(WikiModel.TEAM, club_id))
	assert_true(text.contains("NO FIXTURES LEFT  ·  THE SEASON IS COMPLETE"), "a finished season does not say so")

# --------------------------------------------------------------- helpers ---

## The table laid directly under one section heading; an empty answer when the
## heading is absent or nothing follows it.
func _rows_below(page: Dictionary, section: String) -> Array:
	var seen := false
	for block in page["blocks"]:
		var kind := str(block["k"])
		if kind == "section":
			if seen:
				return []
			seen = str(block["text"]) == section
			continue
		if seen and kind == "table":
			return block["rows"]
		if seen:
			return []
	return []

func _flatten(page: Dictionary) -> String:
	var text := "%s %s" % [page.get("title", ""), page.get("subtitle", "")]
	for block in page.get("blocks", []):
		text += " " + str(block.get("text", ""))
		for row in block.get("rows", []):
			text += " " + " ".join(PackedStringArray(row.get("cells", [])))
		for item in block.get("items", []):
			text += " " + str(item)
	return text

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
