extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_interest")
var CACHE_DIR := TestScratch.dir("cache_test_interest")
const SEED := 2028
const PRISTINE := "_pristine.sqlite"

var season: LeagueSeason = null
var slug := ""

func before_all() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Follow Season", "generated", "fixture_days", SEED)
	assert_not_null(season, "the shared interest season was not created")
	slug = season.save.slug
	_snapshot()

func before_each() -> void:
	season = _fresh()

func after_each() -> void:
	if season != null:
		season.close()
	season = null

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
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)


func _snapshot() -> void:
	if season == null or season.save == null:
		return
	season.save.ensure_open()
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(season.save.path)
	var out := FileAccess.open(SAVE_DIR.path_join(PRISTINE), FileAccess.WRITE)
	if out != null and not bytes.is_empty():
		out.store_buffer(bytes)
		out.close()
	season.save.ensure_open()


func _fresh() -> LeagueSeason:
	if season != null:
		season.close()
		season = null
	PLDatabase.close()
	var bytes := FileAccess.get_file_as_bytes(SAVE_DIR.path_join(PRISTINE))
	var dest := SAVE_DIR.path_join(slug + LeagueSave.EXT)
	var out := FileAccess.open(dest, FileAccess.WRITE)
	assert_true(out != null and not bytes.is_empty(), "the pristine interest save was missing")
	out.store_buffer(bytes)
	out.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the pristine interest save did not reopen")
	return season


func _open_fixtures(club_id: String) -> Array:
	return PLDatabase.rows(
		"SELECT id, watched, home_club_id, away_club_id FROM league_fixture "
		+ "WHERE status <> 'played' AND (home_club_id = ? OR away_club_id = ?);",
		[club_id, club_id])

func _watched(club_id: String) -> int:
	var n := 0
	for fx in _open_fixtures(club_id):
		if int(fx["watched"]) == 1:
			n += 1
	return n


func test_a_new_season_follows_nobody() -> void:
	assert_true(season.record.interest.interests().is_empty(), "a new season already follows a club")
	assert_eq((season.state()["interests"] as Array).size(), 0, "the view lists a followed club")

func test_a_club_the_save_does_not_know_is_refused() -> void:
	assert_false(season.set_interest("NOPE", true), "an unknown club was marked")
	assert_true(season.record.interest.interests().is_empty(), "an unknown club reached the shortlist")

func test_marking_a_club_puts_all_its_games_on_watch() -> void:
	var club_id := str(season.record.standings.table()[0]["club_id"])
	var open := _open_fixtures(club_id).size()
	assert_eq(open, 38, "a generated season does not give the club 38 games")
	assert_true(season.set_interest(club_id, true), "the club was not marked")
	assert_eq(_watched(club_id), open, "not every game of a followed club is on Watch")
	assert_true(season.record.interest.interests().has(club_id), "the shortlist lost the club")
	assert_true((season.state()["interests"] as Array).has(club_id), "the view does not carry the shortlist")

func test_unmarking_reverts_to_auto_unless_the_opponent_is_followed() -> void:
	var fx: Dictionary = _open_fixtures("MUN")[0]
	var home := str(fx["home_club_id"])
	var away := str(fx["away_club_id"])
	var other := _fixture_against_neither(home, away)
	assert_false(other.is_empty(), "the season has no game against a third club")
	season.set_interest(home, true)
	season.set_interest(away, true)
	assert_eq(int(season.record.fixtures.one(str(fx["id"]))["watched"]), 1, "the shared fixture is not on Watch")
	season.set_interest(home, false)
	assert_eq(int(season.record.fixtures.one(str(fx["id"]))["watched"]), 1,
		"unmarking one side dropped a fixture the other side still follows")
	assert_eq(int(season.record.fixtures.one(str(other["id"]))["watched"]), 0,
		"the unmarked club kept its other games on Watch")
	season.set_interest(away, false)
	assert_eq(int(season.record.fixtures.one(str(fx["id"]))["watched"]), 0,
		"both sides unmarked and the fixture stayed on Watch")


func _fixture_against_neither(club_id: String, followed: String) -> Dictionary:
	for fx in _open_fixtures(club_id):
		var other := str(fx["away_club_id"]) if str(fx["home_club_id"]) == club_id else str(fx["home_club_id"])
		if other != followed:
			return fx
	return {}

func test_a_followed_club_s_game_cannot_be_switched_to_auto() -> void:
	var club_id := str(season.record.standings.table()[0]["club_id"])
	season.set_interest(club_id, true)
	var open := _open_fixtures(club_id)
	var fixture_id := str(open[0]["id"])
	assert_false(season.set_watch(fixture_id, false), "a followed fixture was switched to Auto")
	assert_eq(int(season.record.fixtures.one(fixture_id)["watched"]), 1, "the refusal still wrote the flag")

func test_continue_holds_the_clock_for_a_followed_club() -> void:
	var today: Array = season.plan()
	assert_eq(today.size(), 10, "the first matchday does not have ten games")
	var club_id := str(today[0]["home_club_id"])
	season.set_interest(club_id, true)
	var result := season.advance()
	var pending: Array = result.get("pending", [])
	assert_eq(pending.size(), 1, "the followed game was not held for the viewer")
	assert_eq(str(pending[0]["home_club_id"]), club_id, "the wrong game was held")
	assert_eq((result.get("played", []) as Array).size(), 9, "the other games were not settled")
	assert_eq(str(season.record.fixtures.one(str(pending[0]["id"]))["status"]), "pending",
		"the followed game was auto-simmed")


func test_the_shortlist_survives_a_reopen() -> void:
	var club_id := str(season.record.standings.table()[0]["club_id"])
	season.set_interest(club_id, true)
	var slug := season.save.slug
	season.close()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the save did not reopen")
	assert_true(season.record.interest.interests().has(club_id), "the reopened save lost the shortlist")
	assert_eq(_watched(club_id), 38, "the reopened save left the followed club's games on Auto")

func test_a_save_written_before_interest_opens_with_an_empty_shortlist() -> void:
	var club_id := str(season.record.standings.table()[0]["club_id"])
	season.set_interest(club_id, true)
	var path := season.save.path
	var slug := season.save.slug
	season.close()


	PLDatabase.open_path(path)
	PLDatabase.execute("DROP TABLE league_interest;")


	PLDatabase.execute("UPDATE league_fixture SET watched = 0;")
	PLDatabase.reset()
	season = LeagueSeason.open(slug)
	assert_not_null(season, "the older save did not open")
	assert_true(season.record.interest.interests().is_empty(), "the migration invented a shortlist")
	assert_eq(_watched(club_id), 0, "the migration left games on Watch")


func test_the_hub_and_the_table_mark_a_followed_club() -> void:
	var club_id := str(season.plan()[0]["home_club_id"])
	season.set_interest(club_id, true)
	var view := season.state().duplicate()
	view["plan"] = season.plan()
	var hub_items := LeagueSheet.new().hub_layout(Vector2(1200.0, 900.0), view)
	var row := _hub_row(hub_items, str(view["plan"][0]["id"]))
	assert_true((row.get("home_ink", Color.BLACK) as Color).is_equal_approx(
		LeagueInterestMark.ink(LeagueSheet.interest_view(view), club_id)),
		"the hub row is missing the interest mark")
	assert_true((row.get("away_ink", UiChrome.C_TEXT) as Color).is_equal_approx(
		LeagueInterestMark.ink(LeagueSheet.interest_view(view), str(view["plan"][0]["away_club_id"]))),
		"the hub row painted the wrong club's ink")


	var chip := _hub_chip(hub_items, str(view["plan"][0]["id"]))
	assert_true(bool(chip.get("followed", false)), "the followed game still offers an AUTO/WATCH chip")
	assert_eq(str(chip["id"]), "", "the followed game's chip is still a door")


	var table_items: Array = LeagueTableView.new().layout(Vector2(1200.0, 900.0),
		{"table": view["table"], "rules": view["rules"], "interests": view["interests"]})
	var full_row := _item_with(table_items, "table_row", club_id)
	assert_true(bool(full_row.get("interested", false)), "the full table does not mark the followed club")
	var other := _item_with(table_items, "table_row", str(season.record.standings.table()[1]["club_id"]))
	assert_false(bool(other.get("interested", true)), "an unfollowed club is marked too")

func _hub_chip(items: Array, fixture_id: String) -> Dictionary:
	for item in items:
		if str(item["kind"]) != "chip" or not item.has("fixture"):
			continue
		if str((item["fixture"] as Dictionary)["id"]) == fixture_id:
			return item
	return {}

func _hub_row(items: Array, fixture_id: String) -> Dictionary:
	for item in items:
		if str(item["id"]) == "fixture:" + fixture_id:
			return item
	return {}

func _item_with(items: Array, kind: String, club_id: String) -> Dictionary:
	for item in items:
		if str(item["kind"]) != kind:
			continue
		if str(item["id"]) == "club:" + club_id:
			return item
	return {}
