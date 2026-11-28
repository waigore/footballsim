extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_ui_chrome_doors")
var CACHE_DIR := TestScratch.dir("cache_test_ui_chrome_doors")
var PREFS := TestScratch.file("test_ui_chrome_doors.cfg")

var game = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	TestScratch.clear(SAVE_DIR)
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	game.menus.open_menu()

func after_all() -> void:
	if game != null:
		if game.menus.league != null:
			game.menus.league.close()
		game.queue_free()
	LeagueSeason.active = null
	LeagueSaveBoot.close()
	TestScratch.clear(SAVE_DIR)
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func screen():
	return game.menus.league.screen


func _season(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", 11)
	assert_not_null(season, "could not create %s: %s" % [name, LeagueSave.last_error])
	game.menus.league.show_season(season)
	return season

func _leave() -> void:
	if screen().mode == LeagueScreen.MODE_SYSTEM:
		screen().click("sys:menu")
	elif game.menus.league_active():
		screen().click("system")
		screen().click("sys:menu")
	LeagueSystemActions.unload(screen())
	LeagueSaveBoot.close()


func test_the_calendar_month_chips_still_turn_the_page() -> void:
	var season := _season("Chrome Doors")
	screen().click("calendar")
	assert_eq(screen().mode, LeagueScreen.MODE_CALENDAR, "the hub's CALENDAR door did not open")
	var month := str(screen().month)
	var ids: Array = []
	for item in screen().buttons:
		ids.append(str(item["id"]))
	assert_true(ids.has("month:1"), "the calendar lost its next-month chip")
	assert_true(ids.has("month:-1"), "the calendar lost its previous-month chip")
	screen().click("month:1")
	screen().refresh()
	assert_ne(str(screen().month), month, "the next-month chip did not turn the page")
	screen().click("month:-1")
	screen().refresh()
	assert_eq(str(screen().month), month, "the previous-month chip did not turn it back")
	assert_eq(screen().mode, LeagueScreen.MODE_CALENDAR, "turning the page left the calendar")
	assert_not_null(season, "the season went away while reading the calendar")
	_leave()


func test_a_report_goal_plays_its_stored_clip() -> void:
	var season := _season("Chrome Play")


	var settled: Array = season.advance().get("played", [])
	assert_false(settled.is_empty(), "the season could not settle its first matchday")
	var opened := settled[0] as Dictionary
	var played_id := str((opened.get("fixture", {}) as Dictionary).get("id", ""))
	assert_ne(played_id, "", "the settled matchday left no fixture to open")
	screen().show_report(played_id)
	assert_eq(screen().mode, LeagueScreen.MODE_REPORT, "CLICKING a result did not open its report")
	var ids: Array = []
	for item in screen().buttons:
		ids.append(str(item["id"]))
	assert_true(ids.has("back"), "the report lost its BACK door")
	screen().click("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "BACK did not return to the hub")
	_leave()


func test_the_fixture_picker_keeps_its_doors() -> void:
	game.open_select(true)
	var picker = game.selector
	if picker == null:
		return

	picker.queue_redraw()
	await get_tree().process_frame
	var ids: Array = []
	for b in picker.buttons:
		ids.append(str(b["id"]))
	assert_true(ids.has("confirm"), "the picker lost KICK OFF")
	assert_true(ids.has("random"), "the picker lost RANDOM")
	assert_true(ids.has("back"), "the picker lost its way out")
	var home: String = picker.home_id()
	picker.click("home_next")
	assert_ne(picker.home_id(), "", "the home arrow emptied the picker")
	assert_true(picker.home_id() != home or picker.ids.size() == 1,
		"the home arrow did not move off the first club")
	assert_true(ids.has("team_home"), "the picker card is no longer a club door")
	game._close_select()
