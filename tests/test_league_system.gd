extends GdToolsTest

## The System sheet (#109): the season's own save and exit actions, driven through
## the real scene — the hub door, Quick Save, Save As with a typed name, Load that
## unloads the save before the next one opens, Main Menu and the shell's Quit.

const SAVE_DIR := "user://saves_test_system_109"
const CACHE_DIR := "user://cache_test_system_109"
const PREFS := "user://test_league_system_109.cfg"

var game = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
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
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func screen():
	return game.menus.league.screen

func press_id(id: String) -> void:
	for item in screen().buttons:
		if str(item["id"]) == id:
			var at: Vector2 = (item["rect"] as Rect2).get_center()
			var down := InputEventMouseButton.new()
			down.button_index = MOUSE_BUTTON_LEFT
			down.pressed = true
			down.position = at * game.menus.shell.ui_scale
			game._input(down)
			var up := InputEventMouseButton.new()
			up.button_index = MOUSE_BUTTON_LEFT
			up.pressed = false
			up.position = at * game.menus.shell.ui_scale
			game._input(up)
			return
	assert_true(false, "no button %s on screen %s" % [id, screen().mode])

## A season on the hub, created fresh so a case never inherits another's save.
func _season(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", 7)
	assert_not_null(season, "could not create %s: %s" % [name, LeagueSave.last_error])
	game.menus.league.show_season(season)
	return season

## Open the System sheet from the hub door a player presses.
func _system(season: LeagueSeason) -> void:
	game.menus.league.show_season(season)
	press_id("system")
	assert_eq(screen().mode, LeagueScreen.MODE_SYSTEM, "the hub's fourth door did not open System")

func test_the_hub_opens_the_system_sheet_and_back_returns() -> void:
	var season := _season("System Door")
	press_id("system")
	assert_eq(screen().mode, LeagueScreen.MODE_SYSTEM, "the hub door did not open the System sheet")
	var rows: Array = []
	for item in screen().buttons:
		if str(item["kind"]) == "row":
			rows.append(str(item["id"]))
	assert_eq(rows, ["sys:quick", "sys:save", "sys:load", "sys:menu", "sys:quit"],
		"the System sheet is missing an action")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "BACK did not return to the hub")
	assert_not_null(LeagueSeason.active, "BACK out of System unloaded the season")
	_leave()

func test_quick_save_stamps_the_save_and_acknowledges_on_the_sheet() -> void:
	var season := _season("Quick Saved")
	_system(season)
	press_id("sys:quick")
	assert_eq(screen().mode, LeagueScreen.MODE_SYSTEM, "Quick Save left the sheet")
	assert_true(str(screen().sys["status"]).begins_with("SAVED"),
		"Quick Save gave no acknowledgement")
	var saved_at := str(season.save.read_meta().get("saved_at", ""))
	assert_true(saved_at != "", "Quick Save did not stamp the save")
	assert_eq(LeagueSave.current.slug, season.save.slug, "Quick Save moved the live save")
	_leave()

func test_save_as_takes_a_typed_name_and_writes_a_copy() -> void:
	var season := _season("Named Origin")
	_system(season)
	press_id("sys:save")
	assert_true(bool(screen().sys["naming"]), "SAVE AS did not open the name field")
	screen().key(KEY_BACKSPACE)
	screen().key(KEY_BACKSPACE)
	screen().key(KEY_BACKSPACE)
	screen().key(KEY_BACKSPACE)
	screen().key(KEY_C)
	screen().key(KEY_O)
	screen().key(KEY_P)
	screen().key(KEY_Y)
	assert_eq(str(screen().sys["name"]), "Named Origin COPY",
		"the name field did not take the typing")
	press_id("sys:commit")
	assert_false(bool(screen().sys["naming"]), "SAVE AS left the name field open")
	assert_true(str(screen().sys["status"]).begins_with("SAVED AS"),
		"SAVE AS gave no acknowledgement")
	var slugs: Array = []
	for entry in LeagueSave.list():
		slugs.append(str(entry["slug"]))
	assert_true(slugs.has("named-origin-copy"), "the copy is not in the load list")
	assert_eq(season.save.slug, "named-origin", "SAVE AS moved play onto the copy")
	assert_eq(screen().season.save.slug, "named-origin", "the sheet followed the copy")
	_leave()

func test_save_as_writes_the_default_name_without_a_keyboard() -> void:
	var season := _season("No Keyboard")
	_system(season)
	press_id("sys:save")
	press_id("sys:commit")
	assert_eq(screen().mode, LeagueScreen.MODE_SYSTEM, "SAVE AS left the sheet")
	var slugs: Array = []
	for entry in LeagueSave.list():
		slugs.append(str(entry["slug"]))
	assert_true(slugs.has("no-keyboard-copy"), "the default name did not write a copy")
	assert_eq(screen().season.save.slug, "no-keyboard", "the season followed its copy")
	_leave()

## Load is a swap, not a stack: the season in memory, its ledger and the sheets'
## cached readings all belong to the save that is leaving.
func test_load_unloads_the_previous_season_first() -> void:
	var first := _season("Swap A")
	first.advance()
	var first_date := str(first.state()["date"])
	var first_slug := str(first.save.slug)
	var second := _season("Swap B")
	var second_slug := str(second.save.slug)
	game.menus.league.show_season(LeagueSeason.open(first_slug))
	press_id("table")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "the table did not open")
	press_id("back")
	press_id("system")
	press_id("sys:load")
	assert_eq(screen().mode, LeagueScreen.MODE_LOAD, "LOAD did not open the load list")
	press_id("open:" + second_slug)
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "opening a save did not land on its hub")
	assert_eq(LeagueSeason.active.save.slug, second_slug, "the loaded save is not active")
	assert_eq(screen().season.save.slug, second_slug, "the screen kept the old season")
	assert_eq(PLDatabase.current_path(), LeagueSave.current.path,
		"the connection is not on the loaded save")
	assert_eq(LeagueSave.current.slug, second_slug, "the old save is still the live one")
	assert_true((screen().report as Dictionary).is_empty(), "the old report survived the load")
	assert_true((screen().roundup as Array).is_empty(), "the old roundup survived the load")
	assert_eq(screen().book.table.sort, "", "the old table pose survived the load")
	assert_ne(str(LeagueSeason.active.state()["date"]), first_date,
		"the freshly loaded save already played the old one's matchdays")
	_leave()

## A → B → A brings A's own clock and table back, not B's.
func test_a_b_a_keeps_each_seasons_own_state() -> void:
	var a := _season("Cycle A")
	a.advance()
	var a_date := str(a.state()["date"])
	var a_matchday := int(a.state()["matchday"])
	var a_slug := str(a.save.slug)
	var b := _season("Cycle B")
	var b_slug := str(b.save.slug)
	assert_ne(str(b.state()["date"]), a_date, "the two seasons share a clock")
	game.menus.league.show_season(LeagueSeason.open(a_slug))
	for step in [b_slug, a_slug]:
		press_id("system")
		press_id("sys:load")
		press_id("open:" + str(step))
	assert_eq(LeagueSeason.active.save.slug, a_slug, "the round trip did not land on A")
	assert_eq(str(LeagueSeason.active.state()["date"]), a_date, "A lost its clock")
	assert_eq(int(LeagueSeason.active.state()["matchday"]), a_matchday, "A lost its gameweek")
	assert_eq(LeagueSave.current.slug, a_slug, "the connection is not on A")
	_leave()

## Main Menu leaves the sheet for the menu and keeps the season as the menu's
## resume point — only Load takes a save out of memory.
func test_main_menu_returns_to_the_menu_and_keeps_the_session() -> void:
	var season := _season("Leaving")
	_system(season)
	press_id("sys:menu")
	assert_false(game.menus.league_active(), "Main Menu did not leave the league")
	assert_true(game.menus.active(), "Main Menu did not land on the menu")
	assert_not_null(LeagueSeason.active, "Main Menu dropped the session")
	assert_eq(LeagueSave.current.slug, season.save.slug, "Main Menu unbound the save")
	LeagueSystemActions.unload(screen())
	assert_null(LeagueSeason.active, "the unload kept the season")

func test_quit_asks_the_shell_to_confirm() -> void:
	var season := _season("Quitting")
	_system(season)
	press_id("sys:quit")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM,
		"Quit skipped the shell's confirmation")
	assert_not_null(LeagueSeason.active, "Quit unloaded the season before the confirm")
	game.menus.shell.back_to_menu()
	LeagueSystemActions.leave(screen())
	assert_false(game.menus.league_active(), "the league stayed open")
	LeagueSystemActions.unload(screen())
	assert_null(LeagueSeason.active, "the unload kept the season")

func test_back_from_the_load_list_returns_to_the_system_sheet() -> void:
	var season := _season("Load Back")
	_system(season)
	press_id("sys:load")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_SYSTEM,
		"BACK from a load list opened over the season did not return to System")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "BACK from System did not return to the hub")
	_leave()

## Leaving the season the way a player does, so a case never strands one open.
func _leave() -> void:
	if screen().mode == LeagueScreen.MODE_SYSTEM:
		press_id("sys:menu")
	elif game.menus.league_active():
		press_id("system")
		press_id("sys:menu")
	# Every case ends with the save out of memory, so the next one starts clean.
	LeagueSystemActions.unload(screen())
	assert_null(LeagueSeason.active, "a case left a season in memory")

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		DirAccess.make_dir_recursive_absolute(folder)
		for name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
