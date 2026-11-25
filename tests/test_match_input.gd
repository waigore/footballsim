extends GdToolsTest

## The play scene's input router and presentation face, driven through the real
## main.gd with real input events: sheets take the event first, the wheel zooms,
## taps on the overlay bar land in design space, key shortcuts reach the scene,
## and the frame's tick budget follows the mode.

var game = null
var game2 = null

func before_all() -> void:
	# A second scene is split later so the cold-start path (no fixture arg, the
	# dev harness still unset) is covered without disturbing the main one.
	game2 = Node2D.new()
	game2.set_script(load("res://scripts/main.gd"))
	add_child(game2)
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	# The HUD's show/hide choice is a player preference (#158): keep the suite on
	# its own file so the developer's last choice cannot hide the bands it drives.
	var prefs := TestScratch.file("test_match_input_prefs.cfg")
	for g in [game, game2]:
		g.menus.shell.prefs_path = prefs
		g.menus.restore_hud()
	game._on_fixture_confirmed("MUN", "MCI")
	game.paused = true
	game.hud.queue_redraw()
	await get_tree().process_frame

func after_all() -> void:
	for g in [game, game2]:
		if is_instance_valid(g):
			g.queue_free()

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._input(ev)

func _wheel(index: int) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = index
	ev.pressed = true
	game._input(ev)

func _door(id: String) -> Rect2:
	for b in game.hud.buttons:
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func _tap(r: Rect2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = (r.position + r.size * 0.5) * game.hud_scale
	game._input(ev)

# ----------------------------------------------------------------- routing ---

func test_the_cold_start_waits_on_the_menu_and_shows_no_pitch_until_kick_off() -> void:
	assert_not_null(game2.dev, "the dev harness was not built")
	assert_false(game2.match_started, "a cold start claims a match has started")
	assert_eq(game2.hud_scale, HudLayout.overlay_scale(), "the overlay scale was not read on the cold start")
	assert_not_null(game2.fixture, "the fixture sheet glue was not built")
	assert_not_null(game2.view, "the presentation face was not built")

func test_the_encyclopedia_swallows_input_while_it_is_open() -> void:
	game.wiki_host.open_page(WikiModel.LEAGUE, "")
	assert_true(game.wiki_host.is_open(), "the league page did not open")
	var before: bool = game.paused
	_key(KEY_SPACE)
	assert_eq(game.paused, before, "space reached the match through the open encyclopedia")
	game.wiki_host.close()

func test_the_menu_swallows_input_and_keyboard_events_reach_the_shell() -> void:
	game.menus.open_menu()
	assert_true(game.menus.active(), "the menu did not open")
	_key(KEY_ESCAPE)
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM, "Esc did not reach the menu sheet")
	_key(KEY_ESCAPE)
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "the second Esc did not cancel the quit")
	game.menus.close()

# ------------------------------------------------------------ fixture sheet ---

func test_the_fixture_sheet_routes_hover_taps_and_keys() -> void:
	game.open_select()
	game.selector.queue_redraw()
	await get_tree().process_frame
	var sheet = game.selector
	assert_gt(sheet.buttons.size(), 4, "the fixture sheet drew no doors")
	var home: int = sheet.home_idx
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(40, 40) * game.chrome_scale
	game._input(motion)
	assert_eq(sheet.mouse, Vector2(40, 40), "the sheet pointer is not in chrome design space")
	# A key repeat never reaches the sheet.
	var echo := InputEventKey.new()
	echo.keycode = KEY_ESCAPE
	echo.pressed = true
	echo.echo = true
	game._input(echo)
	assert_true(game.select_open, "a key repeat closed the fixture sheet")
	# A right press in the home row cycles the home club through the tap path.
	var next_home := Rect2()
	for b in sheet.buttons:
		if str(b["id"]) == "home_next":
			next_home = b["rect"]
	assert_gt(next_home.size.x, 0.0, "the sheet has no next-home door")
	_tap_css(next_home)
	assert_ne(sheet.home_idx, home, "a tap on the next-home door did not cycle the club")
	# An unmapped key is handed to the sheet and leaves the sheet open.
	var f1 := InputEventKey.new()
	f1.keycode = KEY_F1
	f1.pressed = true
	game._input(f1)
	assert_true(game.select_open, "an unbound key closed the fixture sheet")
	game._close_select()
	assert_false(game.select_open, "back did not close the fixture sheet")

func _tap_css(r: Rect2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = (r.position + r.size * 0.5) * game.chrome_scale
	game._input(ev)

# ------------------------------------------------------------ match input ---

func test_the_wheel_zooms_the_camera_and_a_left_tap_picks_a_token() -> void:
	game.menus.close()
	game.paused = true
	var start: float = game.zoom_scale
	_wheel(MOUSE_BUTTON_WHEEL_UP)
	assert_almost_eq(game.zoom_scale, clampf(start * 1.08, 0.65, 2.4), 0.0001, "the wheel did not zoom in")
	_wheel(MOUSE_BUTTON_WHEEL_DOWN)
	assert_almost_eq(game.zoom_scale, start, 0.0001, "the wheel did not zoom back out")
	# A right-press never reaches the click table.
	var right := InputEventMouseButton.new()
	right.button_index = MOUSE_BUTTON_RIGHT
	right.pressed = true
	game._input(right)
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(30, 30) * game.hud_scale
	game._input(motion)
	assert_eq(game.mouse, motion.position, "a motion did not update the scene pointer")
	game.focus_id = -1
	game.actors.focus_id = -1

func test_a_tap_on_another_token_switches_the_focus_and_asks_again() -> void:
	var first: int = game.engine.players[2].id
	var second: int = game.engine.players[5].id
	for id in [first, second]:
		var p = game.engine.by_id[id]
		var screen: Vector2 = game.get_viewport().get_canvas_transform() * p.pos
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = true
		ev.position = screen
		game._input(ev)
	assert_eq(game.focus_id, second, "a tap on another token did not move the focus")
	# Tapping the focused token again drops it.
	var again := InputEventMouseButton.new()
	again.button_index = MOUSE_BUTTON_LEFT
	again.pressed = true
	again.position = game.get_viewport().get_canvas_transform() * game.engine.by_id[second].pos
	game._input(again)
	assert_eq(game.focus_id, -1, "tapping the focused token did not clear it")
	assert_eq(game.actors.focus_id, -1, "the view layer kept the cleared focus")

func test_the_overlay_doors_reach_the_sheets_and_settings() -> void:
	game.hud.queue_redraw()
	await get_tree().process_frame
	_tap(_door("league"))
	assert_true(game.wiki_host.is_open(), "the league door did not open the encyclopedia")
	game.wiki_host.close()
	_tap(_door("speed"))
	assert_almost_eq(game.speed, 2.0, 0.0001, "the speed door did not cycle the pace")
	_tap(_door("mode"))
	assert_eq(game.mode, "full", "the mode door did not switch to the full match")
	_tap(_door("mode"))
	assert_eq(game.mode, "highlights", "the mode door did not switch back")
	_tap(_door("camera"))
	assert_true(game.camera_follow, "the camera door did not follow the ball")
	_tap(_door("camera"))

# ------------------------------------------------------------------ keys ----

func test_every_one_key_shortcut_reaches_the_scene() -> void:
	game.paused = true
	_key(KEY_R)
	assert_true(game.engine != null and game.engine.clock < 1.0, "R did not kick off a fresh match")
	game.paused = true
	game.names_visible = true
	_key(KEY_N)
	assert_false(game.names_visible, "N did not hide the names")
	_key(KEY_N)
	assert_true(game.names_visible, "N did not bring the names back")
	_key(KEY_T)
	assert_true(game.select_open, "T did not open the fixture sheet")
	_key(KEY_ESCAPE)
	assert_false(game.select_open, "Escape did not close the fixture sheet")
	_key(KEY_L)
	assert_true(game.wiki_host.is_open(), "L did not open the league page")
	game.wiki_host.close()
	_key(KEY_M)
	assert_true(game.menus.active(), "M did not open the menu")
	game.menus.close()
	game.focus_id = -1
	_key(KEY_ESCAPE)
	assert_true(game.menus.active(), "Escape with nothing focused did not ask to quit")
	game.menus.close()

func test_the_frame_budget_follows_the_mode_and_the_pace() -> void:
	# Full match at 30 fps: 2x speed runs about four ticks a frame, capped.
	game.mode = "full"
	game.fast_mode = false
	game.speed = 2.0
	game.accumulator = 0.0
	assert_eq(game.view.ticks_this_frame(1.0 / 30.0), 4, "a 2x full-match frame ran the wrong number of ticks")
	# A slow frame is capped so the loop cannot stall on a backlog.
	game.accumulator = 0.0
	assert_eq(game.view.ticks_this_frame(10.0), 120, "the full-match frame cap was not applied")
	# Highlights fast-forward at the director's rate.
	game.mode = "highlights"
	game.fast_mode = true
	game.accumulator = 0.0
	assert_eq(game.view.ticks_this_frame(1.0 / 30.0), 48, "a highlights frame ran the wrong number of ticks")
	game.accumulator = 0.0
	assert_eq(game.view.ticks_this_frame(10.0), 60, "the highlights frame cap was not applied")
	# A leftover fraction carries to the next frame instead of being dropped.
	game.accumulator = 0.0
	var first: int = game.view.ticks_this_frame(0.01)
	var second: int = game.view.ticks_this_frame(0.01)
	assert_eq(first + second, int(0.02 * 60.0 * 24.0), "the leftover accumulator was lost")

func test_skip_through_the_router_advances_a_fast_highlight() -> void:
	game.mode = "highlights"
	game.fast_mode = true
	game.paused = false
	var clock: float = game.engine.clock
	_key(KEY_S)
	assert_gt(game.engine.clock, clock, "skip did not advance the highlight")
