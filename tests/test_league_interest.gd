extends GdToolsTest

## Teams of Interest inside one league save: the shortlist persists with the
## save, a marked club swings every unplayed fixture to Watch, unmarking gives
## them back to Auto unless the opponent is still marked, and interest never
## changes a score.

var SAVE_DIR := TestScratch.dir("saves_test_interest_103")
var CACHE_DIR := TestScratch.dir("cache_test_interest_103")
const SEED := 4242

var season: LeagueSeason = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	LeagueInterest.current = null
	season = LeagueSeason.create("Interest Season", "generated", "fixture_days", SEED)

func after_all() -> void:
	if season != null:
		season.close()
	season = null
	LeagueInterest.current = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _first_club() -> String:
	var fixtures: Array = season.record.fixtures()
	return str(fixtures[0]["home_club_id"])

func _pending_of(club_id: String) -> Array:
	var out: Array = []
	for fx in season.record.fixtures():
		if str(fx["status"]) == "played":
			continue
		if str(fx["home_club_id"]) == club_id or str(fx["away_club_id"]) == club_id:
			out.append(fx)
	return out

func _watch_of(fixture_id: String) -> int:
	return int(season.record.fixture(fixture_id)["watched"])

## Tests share one season, so each one starts from an empty shortlist.
func _clear_interest() -> void:
	for id in season.interest.all():
		season.interest.set_interest(str(id), false)

# ------------------------------------------------------------- persistence ---

func test_a_new_save_starts_with_no_interest() -> void:
	assert_not_null(season, "the season was not created")
	assert_eq(season.interest.count(), 0, "a new save already has a shortlist")
	assert_eq((season.state()["interest"] as Array).size(), 0, "the state invented interest")
	assert_false(LeagueInterest.marked(_first_club()), "an unmarked club reads as marked")

## A save written before the feature has no row at all: opening it must produce
## an empty set, not an error or a phantom club.
func test_a_save_without_the_row_migrates_to_an_empty_set() -> void:
	var slug := str(season.save.slug)
	PLDatabase.execute("DELETE FROM save_meta WHERE key = ?;", [LeagueInterest.META_KEY])
	season.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the older save did not open")
	assert_eq(season.interest.count(), 0, "the migrated save invented interest")
	# A loosely-spaced legacy value is parsed as ids, never as one long id.
	season.save.put_meta(LeagueInterest.META_KEY, " ARS , LIV ,")
	season.interest.reload()
	assert_true(season.interest.has("ARS"), "a spaced id was dropped")
	assert_true(season.interest.has("LIV"), "the second spaced id was dropped")
	assert_eq(season.interest.count(), 2, "the parser kept blank ids")
	season.interest.set_interest("ARS", false)
	season.interest.set_interest("LIV", false)
	season.save.put_meta(LeagueInterest.META_KEY, "")
	season.interest.reload()

func test_interest_survives_a_reopen_and_reapplies_watch() -> void:
	var club := _first_club()
	assert_true(season.interest.set_interest(club, true), "the mark did not stick")
	var slug := str(season.save.slug)
	season.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the save did not reopen")
	assert_true(season.interest.has(club), "the shortlist did not survive the reload")
	for fx in _pending_of(club):
		assert_eq(int(fx["watched"]), 1, "a pending fixture lost its forced Watch on reload")

# ------------------------------------------------------------------ watch ---

func test_marking_a_club_puts_all_its_unplayed_fixtures_on_watch() -> void:
	var club := _first_club()
	_clear_interest()
	var pending := _pending_of(club)
	assert_gt(pending.size(), 0, "the club has no pending fixtures")
	assert_true(season.interest.set_interest(club, true), "the mark did not stick")
	for fx in pending:
		assert_eq(_watch_of(str(fx["id"])), 1, "an unplayed fixture of the club stayed Auto")
	var plan := season.plan()
	for item in plan:
		if bool(item["watch"]):
			continue
		assert_ne(str(item["home_club_id"]), club, "the planner hid a marked club's Watch")
		assert_ne(str(item["away_club_id"]), club, "the planner hid a marked club's Watch")

func test_unmarking_reverts_to_auto_unless_the_opponent_is_still_marked() -> void:
	var shared: Dictionary = season.record.fixtures()[0]
	var home := str(shared["home_club_id"])
	var away := str(shared["away_club_id"])
	season.interest.set_interest(home, true)
	season.interest.set_interest(away, true)
	assert_eq(_watch_of(str(shared["id"])), 1, "a two-club fixture is not on Watch")
	season.interest.set_interest(home, false)
	assert_eq(_watch_of(str(shared["id"])), 1, "unmarking one side dropped the fixture")
	for fx in _pending_of(home):
		if str(fx["id"]) == str(shared["id"]):
			continue
		if str(fx["home_club_id"]) == away or str(fx["away_club_id"]) == away:
			continue
		assert_eq(_watch_of(str(fx["id"])), 0, "unmarking left another fixture on Watch")
	season.interest.set_interest(away, false)
	assert_eq(_watch_of(str(shared["id"])), 0, "the last unmark did not give the fixture back")

func test_a_manual_auto_is_forced_back_to_watch() -> void:
	var club := _first_club()
	season.interest.set_interest(club, true)
	var fx = _pending_of(club)[0]
	var id := str(fx["id"])
	# A stale Auto can arrive from a hand edit or an older build: the next sync
	# must put it back, and the planner must never paint it Auto meanwhile.
	PLDatabase.execute("UPDATE league_fixture SET watched = 0 WHERE id = ?;", [id])
	season.interest.sync_watch()
	assert_eq(_watch_of(id), 1, "the sync did not force the fixture back")
	season.set_watch(id, false)
	assert_eq(_watch_of(id), 1, "a manual Auto beat the shortlist")
	season.interest.set_interest(club, false)
	season.set_watch(id, false)
	assert_eq(_watch_of(id), 0, "an unmarked club could not go back to Auto")

## Interest moves watch flags only: the same seed must still produce the same
## scores with and without a shortlist.
func test_interest_does_not_move_a_score() -> void:
	var plain := LeagueSeason.create("Plain Score", "generated", "fixture_days", SEED)
	assert_not_null(plain, "the control season was not created")
	var marked_slug := str(season.save.slug)
	season.interest.set_interest(_first_club(), true)
	season.interest.set_interest(_first_club(), false)
	var mine := season.advance()
	var theirs := plain.advance()
	assert_eq((mine["played"] as Array).size(), (theirs["played"] as Array).size(),
		"the shortlist changed how many fixtures played")
	for i in range((mine["played"] as Array).size()):
		var a: Dictionary = (mine["played"] as Array)[i]
		var b: Dictionary = (theirs["played"] as Array)[i]
		assert_eq(str(a["fixture"]["id"]), str(b["fixture"]["id"]), "a different fixture played")
		assert_eq(a["score"], b["score"], "the shortlist moved a score")
	plain.close()
	season = LeagueSeason.open(marked_slug)
	assert_not_null(season, "the interest season did not reopen after the comparison")

func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
