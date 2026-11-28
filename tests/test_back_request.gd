extends GdToolsTest


var PREFS := TestScratch.file("test_back_request.cfg")

var game = null


class FakeInput:
	var events: Array = []

	func handle(event: InputEvent) -> bool:
		events.append(event)
		return true


class FakeMenus:
	var opened := 0

	func active() -> bool:
		return false

	func open_menu() -> void:
		opened += 1


class FakeGame:
	var prematch = null
	var wiki_host = null
	var select_open := false
	var menus = null
	var input = FakeInput.new()
	var replay = null
	var skipped := 0

	func _skip() -> void:
		skipped += 1


func before_all() -> void:
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))


func after_all() -> void:
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	if is_instance_valid(game):
		game.queue_free()


func reset() -> void:
	if game == null:
		return
	if game.prematch != null:
		game.prematch.close()
	if game.wiki_host != null:
		game.wiki_host.close()
	if game.menus != null:
		game.menus.close()
	game.select_open = false
	game.select_from_menu = false
	game.match_started = false
	game.paused = false
	game.result_hold = false
	game.replay = null
	game.back_stamp = -100000


func back() -> void:
	game.back_stamp = -100000
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)


func test_the_project_lets_the_scene_own_the_phone_back_key() -> void:
	assert_false(bool(ProjectSettings.get_setting("application/config/quit_on_go_back", true)),
		"the engine still quits on a phone back press before the scene sees it")
	reset()
	game.menus.open_menu()
	back()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM,
		"back on the main menu did not raise the quit confirmation")
	assert_true(game.menus.shell.visible, "back on the main menu hid the shell")
	back()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU,
		"the second back did not cancel the confirmation")


func test_a_sheet_takes_the_press_and_only_the_sheet() -> void:
	var open_sheet := FakeGame.new()
	open_sheet.select_open = true
	assert_eq(BackPress.press(open_sheet), "sheet", "an open sheet did not take the press")
	assert_eq(open_sheet.input.events.size(), 1, "the sheet was handed no event")
	var event = open_sheet.input.events[0]
	assert_true(event is InputEventKey, "the sheet was handed a pointer event")
	assert_eq(event.keycode, KEY_ESCAPE, "the sheet was not handed the back key")
	assert_true(event.pressed, "the back step was handed as a release")
	assert_eq(open_sheet.skipped, 0, "the press reached the match behind the sheet")

	var clip := FakeGame.new()
	clip.replay = "clip"
	assert_eq(BackPress.press(clip), "clip", "a playing clip did not take the press")
	assert_eq(clip.skipped, 1, "the clip was not skipped")
	assert_true(clip.menus == null, "a clip press opened the menu over the replay")

	var idle := FakeGame.new()
	idle.menus = FakeMenus.new()
	assert_eq(BackPress.press(idle), "menu", "a bare match did not step out to the menu")
	assert_eq(idle.menus.opened, 1, "the menu was not opened")


func test_the_guard_takes_one_step_per_press() -> void:
	assert_false(BackPress.allowed(1000, 1299), "a double delivery inside the guard passed")
	assert_true(BackPress.allowed(1000, 1300), "a second press after the guard was swallowed")
	assert_true(BackPress.allowed(-100000, 0), "the first press of a session was swallowed")

	reset()
	game.menus.open_menu()
	game.back_stamp = Time.get_ticks_msec()
	game._notification(Node.NOTIFICATION_WM_GO_BACK_REQUEST)
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU,
		"one phone press walked two steps (sheet close, then quit)")
	back()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM,
		"the press after the guard did not reach the menu")


func test_back_on_the_fixture_picker_returns_to_the_menu() -> void:
	reset()
	game.menus.open_menu()
	game.open_select(true)
	assert_true(game.select_open, "the picker did not open")
	back()
	assert_false(game.select_open, "back left the picker open")
	assert_true(game.menus.active(), "back did not return to the menu")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "back landed on another screen")


func test_back_on_settings_returns_to_the_menu() -> void:
	reset()
	game.menus.open_menu()
	game.menus.open_settings()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_SETTINGS, "settings did not open")
	back()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "back did not leave settings")


func test_back_on_the_briefing_returns_without_kicking_off() -> void:
	reset()
	game.menus.open_menu()
	game.open_select(true)
	game._on_fixture_confirmed("ENG-ARS1", "ENG-LIV1")
	assert_true(TestBriefing.is_open(game), "KICK OFF skipped the briefing")
	back()
	assert_false(TestBriefing.is_open(game), "back left the briefing up")
	assert_false(game.match_started, "back started the match")
	assert_true(game.select_open, "back from the picker's briefing did not return to the picker")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_NONE,
		"back from the briefing left a sheet over the picker")


func test_back_on_the_encyclopedia_closes_it_and_keeps_the_session() -> void:
	reset()
	game.menus.open_menu()
	game.open_select(true)
	game.wiki_host.open_page(WikiModel.LEAGUE, "")
	assert_true(game.wiki_host.is_open(), "the encyclopedia did not open")
	back()
	assert_false(game.wiki_host.is_open(), "back left the encyclopedia up")
	assert_true(game.select_open, "closing the encyclopedia dropped the picker underneath")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_NONE,
		"back from the encyclopedia left a sheet over the picker")


func test_back_in_a_match_opens_the_menu_instead_of_quitting() -> void:
	reset()
	game.fixture.start("ENG-ARS1", "ENG-LIV1")
	assert_true(game.match_started, "the match did not start")
	var phase := str(game.engine.phase)
	back()
	assert_true(game.menus.active(), "back in a match did not open the menu")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "back in a match raised another screen")
	assert_true(game.paused, "the match kept playing behind the menu")
	assert_eq(str(game.engine.phase), phase, "back in a match disturbed the match")
	assert_eq(MenuScreen.primary_id(bool(game.menus.shell.has_match)), "resume",
		"the menu back raised does not offer the waiting match")
	back()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM,
		"back on the menu did not ask before leaving the game")
