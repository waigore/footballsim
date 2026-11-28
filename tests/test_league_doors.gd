extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_league_doors")
var CACHE_DIR := TestScratch.dir("cache_test_league_doors")
const SEED := 411

var season: LeagueSeason = null
var screen: LeagueScreen = null
var asked: Array = []

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Doors Season", "generated", "fixture_days", SEED)
	screen = LeagueScreen.new()
	add_child(screen)
	screen.season = season
	screen.mode = LeagueScreen.MODE_HUB

func after_all() -> void:
	if screen != null:
		screen.queue_free()
		screen = null
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

func _hub() -> void:
	screen.season = season
	screen.mode = LeagueScreen.MODE_HUB


	screen.visible = true

func _fixture(watched: int = 0) -> Dictionary:
	for fx in season.record.fixtures.all():
		if str(fx["status"]) == "pending":
			season.set_watch(str(fx["id"]), watched == 1)
			return season.record.fixtures.one(str(fx["id"]))
	return {}

func test_the_key_map_walks_a_sheet_without_a_window() -> void:
	_hub()


	for code in [KEY_UP, KEY_W, KEY_DOWN, KEY_S, KEY_PAGEUP, KEY_PAGEDOWN, KEY_HOME, KEY_END]:
		assert_true(screen.key(code), "the sheet did not take scroll key %d" % code)
	assert_false(screen.key(KEY_TAB), "an unbound key was taken")
	var body := screen.body
	screen.body = null
	assert_true(screen.key(KEY_DOWN), "a screen without a window stopped taking scroll keys")
	screen.body = body

func test_enter_continues_the_hub_and_escape_walks_it_back() -> void:
	_hub()
	screen.nav.clear()
	assert_true(screen.key(KEY_ENTER), "Enter did not press Continue")
	assert_ne(screen.mode, LeagueScreen.MODE_HUB, "Continue left the hub without settling")

	screen.mode = LeagueScreen.MODE_HUB
	screen.nav.clear()
	screen.click("table")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "the table door did not open the table")
	assert_true(screen.key(KEY_ESCAPE), "Esc was not taken on a reading")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "Esc did not return to the hub")

	assert_true(screen.key(KEY_BACKSPACE), "Backspace was not taken on the hub")
	assert_true(screen.visible, "BACK at the root closed the season")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "BACK at the root moved the sheet")
	screen.close()

func test_the_wizard_and_the_report_take_their_own_keys() -> void:
	screen.mode = LeagueScreen.MODE_WIZARD
	screen.wizard = {"name": "", "calendar_mode": "generated", "advance_mode": "fixture_days", "error": ""}
	assert_true(screen.key(KEY_A), "the wizard did not take a letter")
	assert_eq(str(screen.wizard["name"]), "A", "the typed letter did not reach the name")
	screen.mode = LeagueScreen.MODE_REPORT
	screen.report = {"fixture": {"id": "gw01-HOM-AWY"}, "events": [], "highlights": []}
	assert_false(screen.key(KEY_5), "a goal key with no clip was taken")
	assert_false(screen.has_clip(0), "an empty report claims a clip")

func test_the_pose_doors_move_the_surface_between_its_sheets() -> void:
	_hub()
	screen.nav.clear()
	screen.click("table")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "the table door did not open the table")
	screen.click("calendar")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "the calendar door did not open the calendar")
	screen.click("podium")
	assert_eq(screen.mode, LeagueScreen.MODE_PODIUM, "the podium door did not open the podium")

	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "BACK did not return to the calendar")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "BACK did not return to the table")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "BACK did not return to the hub")
	assert_true(screen.visible, "BACK at the root closed the surface")
	screen.click("")
	assert_true(screen.visible, "an empty press reopened something")

	screen.mode = LeagueScreen.MODE_PODIUM
	screen.refresh()
	screen.click("menu")
	assert_false(screen.visible, "MAIN MENU did not close the surface")

func test_the_table_door_opens_without_a_season() -> void:
	screen.season = null
	screen.click("table")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "the table door needed a season it does not")
	screen.click("tbl:sort:club")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "a table press left the table")

func test_the_simple_doors_reach_the_surface_and_the_season() -> void:
	asked = []
	screen.club_requested.connect(func(id: String) -> void: asked.append("club:" + id))
	_hub()
	screen.click("club:ENG-MCI1")
	assert_eq(asked, ["club:ENG-MCI1"], "a club row did not ask for the team page")
	screen.click("suggest")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "the Suggest door moved the surface")
	screen.click("name")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "a repaint door changed the pose")
	screen.click("mode:real")
	assert_eq(str(screen.wizard["calendar_mode"]), "real", "a wizard choice was not taken")
	screen.click("adv:every_day")
	assert_eq(str(screen.wizard["advance_mode"]), "every_day", "an advance choice was not taken")

func test_continue_settles_a_day_and_opens_the_roundup() -> void:
	_hub()
	screen.click("continue")
	assert_eq(screen.mode, LeagueScreen.MODE_REPORT, "the settled day did not show its roundup")
	assert_false((screen.roundup as Array).is_empty(), "the roundup is empty")

func test_continue_opens_a_pending_watch_before_settling() -> void:
	asked = []
	screen.match_requested.connect(func(home: String, away: String, fixture_id: String) -> void:
		asked.append(fixture_id))
	_hub()
	var fx := _fixture(1)
	screen.click("continue")
	assert_eq(asked, [str(fx["id"])], "Continue did not open the watched fixture")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "a pending watch left the hub")

func test_continue_is_inert_without_a_season_or_while_finishing() -> void:
	screen.season = null
	screen.mode = LeagueScreen.MODE_HUB
	screen.click("continue")
	assert_null(screen.season, "Continue invented a season")
	_hub()
	var before := str(season.state()["date"])
	season.finishing = true
	screen.click("continue")
	assert_eq(str(season.state()["date"]), before, "Continue moved the clock while finishing")
	season.finishing = false


	screen.mode = LeagueScreen.MODE_REPORT
	screen.nav.clear()
	screen.click("continue")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "a root Results reading did not land on the hub")

func test_a_fixture_row_watches_starts_or_opens_a_report() -> void:
	asked = []
	screen.match_requested.connect(func(_home: String, _away: String, fixture_id: String) -> void:
		asked.append(fixture_id))
	_hub()
	var fx := _fixture(0)
	screen.click("toggle:" + str(fx["id"]))
	assert_eq(int(season.record.fixtures.one(str(fx["id"]))["watched"]), 1, "the toggle did not watch the fixture")
	screen.click("fixture:" + str(fx["id"]))
	assert_eq(asked, [str(fx["id"])], "a watched fixture did not start its match")
	season.set_watch(str(fx["id"]), false)
	screen.click("fixture:" + str(fx["id"]))
	assert_eq(int(season.record.fixtures.one(str(fx["id"]))["watched"]), 1, "a pending row did not flip its watch")
	var played := {}
	for row in season.record.fixtures.all():
		if str(row["status"]) == "played":
			played = row
			break
	if not played.is_empty():
		screen.click("fixture:" + str(played["id"]))
		assert_eq(screen.mode, LeagueScreen.MODE_REPORT, "a played fixture did not open its report")
		screen.mode = LeagueScreen.MODE_HUB
		screen.click("toggle:" + str(played["id"]))
		assert_eq(int(season.record.fixtures.one(str(played["id"]))["watched"]),
			int(played["watched"]), "a played fixture changed its watch")

func test_fixture_rows_are_inert_without_a_season_and_ignore_unknown_ids() -> void:
	screen.season = null
	screen.click("toggle:gw01-HOM-AWY")
	screen.click("fixture:gw01-HOM-AWY")
	assert_null(screen.season, "a fixture row invented a season")
	_hub()
	var watched := 0
	for row in season.record.fixtures.all():
		watched += int(row["watched"])
	screen.click("fixture:no-such-fixture")
	screen.click("toggle:no-such-fixture")
	var after := 0
	for row in season.record.fixtures.all():
		after += int(row["watched"])
	assert_eq(after, watched, "an unknown fixture changed a watch flag")

func test_a_report_row_opens_the_sheet_for_its_fixture() -> void:
	_hub()
	var played := ""
	for row in season.record.fixtures.all():
		if str(row["status"]) == "played":
			played = str(row["id"])
			break
	assert_true(played != "", "the settled day left no played fixture")
	screen.click("match:" + played)
	assert_eq(screen.mode, LeagueScreen.MODE_REPORT, "a report row did not open its report")
	assert_eq(str((screen.report.get("fixture", {}) as Dictionary).get("id", "")), played,
		"the report is for another fixture")

func test_a_goal_door_plays_a_stored_clip_and_names_its_fixture() -> void:
	var played: Array = []
	screen.goal_highlight_requested.connect(func(fixture_id: String, index: int) -> void:
		played.append("%s#%d" % [fixture_id, index]))
	_hub()
	screen.click("goal:0")
	assert_true(played.is_empty(), "a goal away from the report was played")
	screen.mode = LeagueScreen.MODE_REPORT
	screen.report = {"fixture": {"id": "gw01-HOM-AWY"}, "highlights": [{"goal_index": 0}]}
	assert_true(screen.has_clip(0), "the report's own goal clip was not seen")
	screen.click("goal:0")
	assert_eq(played, ["gw01-HOM-AWY#0"], "the goal door did not name the clip's fixture")
	assert_true(screen.key(KEY_1), "the report's goal key was not taken")
	assert_eq(played.size(), 2, "the report's goal key did not play the clip")

func test_the_moved_doors_answer_on_their_own() -> void:


	LeagueGoalDoors.play(screen, 7)
	assert_false(LeagueGoalDoors.has_clip(screen, 7), "an ordinal the report never stored claimed a clip")
	screen.mode = LeagueScreen.MODE_REPORT
	screen.report = {"fixture": {"id": "gw01-HOM-AWY"}, "highlights": [{"goal_index": 0}]}
	assert_false(LeagueGoalDoors.has_clip(screen, 3), "a missing ordinal claimed a clip")
	_hub()
	assert_false(LeagueSeasonDoors.set_interest(screen, "", true), "an empty club is never a shortlist entry")
	assert_true(LeagueSeasonDoors.set_interest(screen, "ENG-ARS1", true), "an add was refused")
	assert_eq(str(screen.interest_query), "", "an add kept the search")
	assert_true(LeagueSeasonDoors.set_interest(screen, "ENG-ARS1", false), "a remove was refused")
	screen.season = null
	assert_false(LeagueSeasonDoors.set_interest(screen, "ENG-ARS1", true), "a surface with no season took a shortlist")
	screen.mode = LeagueScreen.MODE_STATS
	LeagueSeasonDoors.open_day(screen, "1990-01-01")
	assert_eq(screen.mode, LeagueScreen.MODE_STATS, "a day with no season moved the sheet")
	assert_eq(screen.report_back, LeagueScreen.MODE_HUB, "an inert day door moved the report's return")

func test_the_panel_doors_jump_pose_and_bind_the_table() -> void:


	_hub()
	var depth: int = screen.nav.depth()
	LeaguePanelDoors.nav(screen, "table")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "the table destination did not open the table")

	assert_false(screen.panel.is_open(), "the panel did not head back in")
	assert_eq(screen.book.table.order.key, str(season.save.read_meta().get(LeagueTableView.META_SORT, "")),
		"the table did not read the season save's own sort")
	assert_eq(screen.nav.depth(), depth + 1, "the jump did not become one page of history")
	LeaguePanelDoors.nav(screen, "interest")
	assert_eq(screen.mode, LeagueScreen.MODE_INTEREST, "the shortlist does not open from its panel row")
	assert_eq(str(screen.interest_query), "", "the shortlist kept a search it never asked for")
	LeaguePanelDoors.nav(screen, "calendar")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "the calendar does not open from its panel row")
	assert_false(screen.days_cache.is_empty(), "the calendar opened with no day index")
	LeaguePanelDoors.stats(screen, "stats:podium")
	assert_eq(screen.mode, LeagueScreen.MODE_PODIUM, "the podium does not open from the Stats sheet")
	LeaguePanelDoors.stats(screen, "stats:reports")
	assert_eq(screen.mode, LeagueScreen.MODE_STATS, "the reports reading did not come back")
	_hub()
	LeaguePanelDoors.nav(screen, "fixtures")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "Today's Fixtures did not land on the hub")
	LeaguePanelDoors.nav(screen, "cups")
	assert_eq(screen.mode, LeagueScreen.MODE_CUPS, "CUPS does not open from its panel row")
	var held := LeagueSeasonDoors._held([
		{"id": "a", "watched": 0}, {"id": "b", "watched": 1}, {"id": "c", "watched": 0},
	])
	assert_eq(str(held["id"]), "b", "Continue did not prefer the watched tie")
	var first := LeagueSeasonDoors._held([{"id": "only", "watched": 0}])
	assert_eq(str(first["id"]), "only", "Continue lost the only pending fixture")

func test_deleting_the_open_save_unloads_it_first() -> void:

	var throwaway := LeagueSeason.create("Doors Throwaway", "generated", "fixture_days", SEED + 1)
	assert_not_null(throwaway, "the throwaway season was not created")
	screen.season = throwaway
	screen.mode = LeagueScreen.MODE_LOAD
	screen.saves = LeagueSaveCatalog.list()
	screen.refresh()
	var slug := throwaway.save.slug
	screen.click("delete:" + slug)
	assert_true(screen.delete.is_open(), "the delete door did not ask")
	assert_eq(screen.delete.name, "Doors Throwaway", "the question did not name the save")
	assert_true(screen.season == throwaway, "asking to delete unloaded the season already")
	var still: Array = []
	for row in LeagueSaveCatalog.list():
		still.append(str(row["slug"]))
	assert_true(still.has(slug), "the save went before the answer")


	screen.click("delete_yes")
	assert_null(screen.season, "the deleted save stayed bound to the surface")
	assert_false(screen.delete.is_open(), "the question outlived its answer")
	var left: Array = []
	for row in LeagueSaveCatalog.list():
		left.append(str(row["slug"]))
	assert_false(left.has(slug), "the deleted save is still on disk")

	var copy := season.save.write_copy("Doors other copy")
	assert_true(copy != "", "the stand-in save was not written")
	screen.season = season
	screen.saves = LeagueSaveCatalog.list()
	screen.refresh()
	screen.click("delete:" + copy)
	assert_eq(screen.season, season, "asking to delete another save unloaded the open one")
	screen.click("delete_yes")
	assert_eq(screen.season, season, "deleting another save unloaded the open one")
	assert_false(screen.delete.is_open(), "the question outlived its answer")

func test_the_delete_question_is_a_door_of_its_own() -> void:

	var copy := season.save.write_copy("Doors kept copy")
	assert_true(copy != "", "the kept save was not written")
	screen.season = season
	screen.mode = LeagueScreen.MODE_LOAD
	screen.saves = LeagueSaveCatalog.list()
	screen.refresh()
	var vp: Vector2 = screen.design_vp()
	screen.click("delete:" + copy)
	assert_eq(screen.button_at(ConfirmPrompt.confirm_rect(vp).get_center()), "delete_yes",
		"the dialog's DELETE is not its own door")
	assert_eq(screen.button_at(ConfirmPrompt.cancel_rect(vp).get_center()), "delete_no",
		"the dialog's CANCEL is not its own door")
	assert_eq(screen.button_at(Vector2(4.0, vp.y - 4.0)), "", "a press behind the dialog reached the list")
	screen.overlay._process(0.0)
	assert_true(screen.key(KEY_ESCAPE), "Esc was not taken by the dialog")
	assert_false(screen.delete.is_open(), "Esc did not put the question away")
	var kept: Array = []
	for row in LeagueSaveCatalog.list():
		kept.append(str(row["slug"]))
	assert_true(kept.has(copy), "cancelling deleted the save")

	screen.click("delete:" + copy)
	screen.click("delete_no")
	assert_false(screen.delete.is_open(), "the dialog's CANCEL did not put the question away")

	screen.click("delete:" + copy)
	assert_true(screen.key(KEY_ENTER), "Enter was not taken by the dialog")
	assert_false(screen.delete.is_open(), "Enter did not answer the dialog")
	var gone: Array = []
	for row in LeagueSaveCatalog.list():
		gone.append(str(row["slug"]))
	assert_false(gone.has(copy), "Enter did not delete the save")
	assert_eq(screen.mode, LeagueScreen.MODE_LOAD, "answering the dialog left the load list")
