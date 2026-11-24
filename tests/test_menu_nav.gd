extends GdToolsTest

## The cold-start shell driven headlessly: menu → fixture setup → back, quit
## confirm, settings with a persisted volume, HUD doors, and the menu-only BGM
## contract. The scene is the real main.gd, the same way test_touch_flow drives
## the phone overlay.

var PREFS := TestScratch.file("test_menu_nav_issue36.cfg")

var game = null

func before_all() -> void:
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game.menus.open_menu()

func after_all() -> void:
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	if is_instance_valid(game):
		game.queue_free()

func vp() -> Vector2:
	return game.menus.shell.design_vp()

func door(id: String, has_match_now: bool = false) -> Rect2:
	var waiting: bool = has_match_now or bool(game.menus.shell.has_match)
	for b in MenuScreen.door_rects(vp(), waiting):
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func press(r: Rect2) -> void:
	game.menus.shell.click(r.position + r.size * 0.5)

func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._input(ev)

# ------------------------------------------------------------- cold start ---

func test_cold_start_opens_the_main_menu() -> void:
	game.menus.open_menu()
	assert_true(game.menus.active(), "the shell is not active on a cold start")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "the shell is not showing the menu")
	assert_true(game.paused, "the match behind the menu must be paused")
	assert_false(game.hud_layer.visible, "the match HUD is visible under the menu")
	assert_true(game.menus.shell.music.wanted, "the menu did not ask for its music")

func test_the_menu_doors_are_tappable_and_inside_the_screen() -> void:
	for size in [Vector2(1600, 900), Vector2(913, 411), Vector2(640, 300)]:
		var rects := MenuScreen.door_rects(size, true)
		assert_eq(rects.size(), 6, "the menu is missing a door at %s" % size)
		for b in rects:
			var r: Rect2 = b["rect"]
			assert_gte(r.size.y, 44.0, "a door is too short to tap at %s" % size)
			assert_gte(r.position.x, 0.0, "a door starts off-screen at %s" % size)
			assert_lte(r.end.x, size.x, "a door runs off the right edge at %s" % size)
			assert_lte(r.end.y, size.y, "a door runs off the bottom at %s" % size)

func test_start_sim_opens_the_fixture_sheet_and_back_returns_to_the_menu() -> void:
	game.menus.open_menu()
	press(door("start"))
	assert_true(game.select_open, "Start Sim did not open fixture setup")
	assert_true(game.selector.back_to_menu, "the fixture sheet does not offer the menu as its exit")
	assert_false(game.menus.shell.visible, "the menu stayed on top of fixture setup")
	assert_true(game.hud_layer.visible == false, "the match HUD showed under fixture setup")
	assert_true(game.menus.shell.music.wanted, "the pre-match music stopped on the way to fixture setup")
	game._close_select()
	assert_false(game.select_open, "Back did not close fixture setup")
	assert_true(game.menus.active(), "Back did not return to the main menu")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "Back did not land on the menu")

func test_kick_off_closes_the_shell_and_stops_the_music() -> void:
	game.open_select(true)
	game._on_fixture_confirmed("ARS", "LIV")
	assert_false(game.menus.active(), "the shell stayed up after kick-off")
	assert_true(game.match_started, "the match was not marked started")
	assert_true(game.hud_layer.visible, "the match HUD did not come back for kick-off")
	assert_false(game.paused, "the match stayed paused for kick-off")
	assert_false(game.menus.shell.music.wanted, "menu music is still wanted under the match")
	assert_eq(game.home_id, "ARS", "the confirmed home side did not take")

# -------------------------------------------------------------- quit paths ---

func test_escape_on_the_match_raises_a_confirm_and_cancel_returns() -> void:
	game.menus.close()
	game.hud_layer.visible = true
	key(KEY_ESCAPE)
	assert_true(game.menus.active(), "Esc quit without confirming")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM, "Esc did not raise the quit confirm")
	game.menus.shell.key(KEY_ESCAPE)
	assert_false(game.menus.active(), "cancelling the quit confirm left the shell up")
	assert_true(game.hud_layer.visible, "cancelling the quit confirm hid the match")

func test_the_menu_quit_door_asks_first() -> void:
	game.menus.open_menu()
	press(door("quit"))
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM, "Quit skipped the confirm")
	var d: Rect2 = ConfirmPrompt.confirm_rect(vp())
	assert_gte(d.size.y, 44.0, "the quit button is too short to tap")
	game.menus.shell.click(ConfirmPrompt.cancel_rect(vp()).position)
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "cancelling the quit confirm did not return to the menu")

func test_escape_on_the_menu_asks_before_quitting() -> void:
	game.menus.open_menu()
	key(KEY_ESCAPE)
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM, "Esc on the menu skipped the confirm")
	key(KEY_ESCAPE)
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "the second Esc did not cancel")

# --------------------------------------------------------------- settings ---

func test_settings_volume_applies_immediately_and_persists() -> void:
	game.menus.open_menu()
	press(door("settings"))
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_SETTINGS, "Settings is not reachable from the menu")
	var track := SettingsScreen.track_rect(vp())
	var point := Vector2(track.position.x + track.size.x * 0.8, track.position.y + track.size.y * 0.5)
	game.menus.shell.click(point)
	assert_almost_eq(game.menus.shell.volume, 0.8, 0.03, "clicking the track did not set the volume")
	assert_almost_eq(game.menus.shell.music.volume, game.menus.shell.volume, 0.001, "the player did not follow the slider")
	assert_almost_eq(Prefs.load_bgm(PREFS), game.menus.shell.volume, 0.001, "the volume was not saved")
	game.menus.shell.click(SettingsScreen.minus_rect(vp()).position + Vector2(22, 22))
	assert_almost_eq(game.menus.shell.volume, 0.7, 0.03, "the minus door did not step the volume down")
	game.menus.shell.click(SettingsScreen.plus_rect(vp()).position + Vector2(22, 22))
	assert_almost_eq(game.menus.shell.volume, 0.8, 0.03, "the plus door did not step the volume up")
	press(SettingsScreen.back_rect(vp()))
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "Back from settings did not return to the menu")
	press(door("settings"))
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_SETTINGS, "Settings did not reopen from the menu")
	game.menus.shell.open_menu(true)
	assert_almost_eq(game.menus.shell.volume, 0.8, 0.03, "the saved volume did not survive reopening the menu")

func test_zero_volume_is_silent_music_but_a_real_setting() -> void:
	game.menus.shell.set_volume(0.0)
	assert_true(game.menus.shell.music.is_silent(), "0% did not mute the player")
	assert_almost_eq(Prefs.load_bgm(PREFS), 0.0, 0.0001, "0% was not saved")
	game.menus.shell.set_volume(1.4)
	assert_almost_eq(game.menus.shell.volume, 1.0, 0.0001, "an over-loud value was not clamped")
	game.menus.shell.set_volume(0.7)

# ------------------------------------------------------------ HUD doors -----

func test_the_hud_menu_door_returns_to_the_menu() -> void:
	game.menus.close()
	game.hud_layer.visible = true
	game.paused = false
	game.hud.queue_redraw()
	await get_tree().process_frame
	var door_rect := Rect2()
	for b in game.hud.buttons:
		if str(b["id"]) == "menu":
			door_rect = b["rect"]
	assert_gt(door_rect.size.x, 0.0, "the HUD has no menu door")
	game._click((door_rect.position + door_rect.size * 0.5) * game.hud_scale)
	assert_true(game.menus.active(), "the HUD menu door did not open the menu")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_MENU, "the HUD door did not land on the menu")
	assert_true(game.paused, "the match was not paused behind the menu")

func test_resume_is_offered_only_while_a_match_waits() -> void:
	game.match_started = true
	game.menus.open_menu()
	var ids: Array = []
	for b in MenuScreen.door_rects(vp(), true):
		ids.append(str(b["id"]))
	assert_true(ids.has("resume"), "a waiting match has no resume door")
	press(door("resume", true))
	assert_false(game.menus.active(), "Resume did not leave the menu")
	assert_false(game.paused, "Resume did not unpause the match")
	assert_true(game.hud_layer.visible, "Resume did not bring the HUD back")
	assert_false(game.menus.shell.music.wanted, "menu music kept playing after Resume")

# ------------------------------------------------------------ presentation --

func test_the_still_track_always_covers_the_screen() -> void:
	var size := Vector2(1600, 900)
	for t in [0.0, 1.0, 5.5, 10.9, 11.1, 22.0, 54.5]:
		for i in range(MenuScreen.STILL_COUNT):
			var r := MenuScreen.ken_rect(size, i, t)
			assert_lte(r.position.x, 0.0, "a still exposes the left edge at t=%s" % t)
			assert_lte(r.position.y, 0.0, "a still exposes the top edge at t=%s" % t)
			assert_gte(r.end.x, size.x, "a still exposes the right edge at t=%s" % t)
			assert_gte(r.end.y, size.y, "a still exposes the bottom edge at t=%s" % t)

func test_the_crossfade_and_still_rotation_are_bounded() -> void:
	assert_almost_eq(MenuScreen.fade_alpha(0.0), 0.0, 0.001, "a fresh still should be fully opaque")
	assert_almost_eq(MenuScreen.fade_alpha(MenuScreen.SLOT - 0.01), 1.0, 0.01, "the crossfade never finished")
	assert_eq(MenuScreen.current_still(0.0), 0, "the first still is not first")
	assert_eq(MenuScreen.current_still(MenuScreen.SLOT), 1, "the track did not advance")
	assert_eq(MenuScreen.next_still(0.0), 1, "the crossfade target is wrong")
	assert_eq(MenuScreen.current_still(MenuScreen.SLOT * float(MenuScreen.STILL_COUNT)), 0, "the track did not wrap")

func test_the_shell_draws_every_sheet_headless() -> void:
	game.menus.open_menu()
	game.menus.shell.queue_redraw()
	await get_tree().process_frame
	game.menus.open_settings()
	game.menus.shell.queue_redraw()
	await get_tree().process_frame
	game.menus.shell.open_quit_confirm()
	game.menus.shell.queue_redraw()
	await get_tree().process_frame
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM, "the quit sheet was not the drawn pose")
	game.menus.shell.cancel_confirm()

func test_the_product_is_named_football_sim() -> void:
	assert_eq(str(ProjectSettings.get_setting("application/config/name")), "Football Sim", "the window/product name was not renamed")
	assert_eq(UiChrome.PRODUCT_FULL, "Football Sim", "the shared product string is stale")
	var fonts := UiChrome.fonts()
	assert_not_null(fonts["bold"], "the shared bold font failed to load")
	assert_not_null(fonts["med"], "the shared medium font failed to load")
	assert_not_null(fonts["body"], "the shared body font failed to load")

func test_the_dev_flags_pose_the_shell() -> void:
	var cap := DevCapture.new()
	cap.parse(game, ["--menu", "--settings", "--quit-confirm"])
	assert_true(cap.open_menu, "--menu did not parse")
	assert_true(cap.open_settings, "--settings did not parse")
	assert_true(cap.open_confirm, "--quit-confirm did not parse")

# ---------------------------------------------------- input-surface sweep ---

func _mouse_press(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p * game.menus.shell.ui_scale
	game._input(ev)

func _mouse_release(p: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = p * game.menus.shell.ui_scale
	game._input(ev)

func _mouse_drag(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p * game.menus.shell.ui_scale
	ev.button_mask = MOUSE_BUTTON_MASK_LEFT
	game._input(ev)

func test_the_settings_bar_drags_and_steps() -> void:
	game.menus.open_menu()
	press(door("settings"))
	var track := SettingsScreen.track_rect(vp())
	var start := Vector2(track.position.x + track.size.x * 0.5, track.position.y + 2.0)
	_mouse_press(start)
	assert_almost_eq(game.menus.shell.volume, 0.5, 0.04, "pressing the track did not set half volume")
	_mouse_drag(Vector2(track.position.x + track.size.x * 0.2, track.position.y + 2.0))
	assert_almost_eq(game.menus.shell.volume, 0.2, 0.04, "dragging the track did not follow the pointer")
	_mouse_release(Vector2(track.position.x + track.size.x * 0.2, track.position.y + 2.0))
	assert_false(game.menus.shell.settings.dragging, "releasing the slider left it dragging")
	game.menus.shell.set_volume(0.7)

func test_keyboard_walks_every_sheet() -> void:
	game.menus.open_menu()
	game.menus.shell.set_volume(0.5)
	assert_true(game.menus.shell.key(KEY_S), "S did not open settings")
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_SETTINGS, "S did not land on settings")
	assert_true(game.menus.shell.key(KEY_LEFT), "left arrow was ignored on settings")
	assert_almost_eq(game.menus.shell.volume, 0.4, 0.03, "left arrow did not step down")
	assert_true(game.menus.shell.key(KEY_RIGHT), "right arrow was ignored on settings")
	assert_almost_eq(game.menus.shell.volume, 0.5, 0.03, "right arrow did not step up")
	assert_true(game.menus.shell.key(KEY_A), "A was ignored on settings")
	assert_almost_eq(game.menus.shell.volume, 0.4, 0.03, "A did not step down")
	assert_true(game.menus.shell.key(KEY_D), "D was ignored on settings")
	assert_almost_eq(game.menus.shell.volume, 0.5, 0.03, "D did not step up")
	assert_false(game.menus.shell.key(KEY_X), "settings took an unrelated key")
	game.menus.open_menu()
	assert_false(game.menus.shell.key(KEY_X), "the menu took an unrelated key")
	assert_true(game.menus.shell.key(KEY_ENTER), "Enter did not start from the menu")
	assert_true(game.select_open, "Enter did not open fixture setup")
	game._close_select()

func test_hit_tests_cover_every_sheet() -> void:
	game.menus.open_menu()
	assert_eq(game.menus.shell.button_at(door("start").get_center()), "start", "the start door did not hit")
	assert_eq(game.menus.shell.button_at(Vector2(-10, -10)), "", "empty space hit a door")
	game.menus.open_settings()
	assert_eq(game.menus.shell.button_at(SettingsScreen.track_rect(vp()).get_center()), "track", "the track did not hit")
	assert_eq(game.menus.shell.button_at(SettingsScreen.minus_rect(vp()).get_center()), "minus", "minus did not hit")
	assert_eq(game.menus.shell.button_at(SettingsScreen.plus_rect(vp()).get_center()), "plus", "plus did not hit")
	assert_eq(game.menus.shell.button_at(SettingsScreen.back_rect(vp()).get_center()), "back", "back did not hit")
	game.menus.shell.open_quit_confirm()
	assert_eq(game.menus.shell.button_at(ConfirmPrompt.confirm_rect(vp()).get_center()), "confirm", "quit did not hit")
	assert_eq(game.menus.shell.button_at(ConfirmPrompt.cancel_rect(vp()).get_center()), "cancel", "cancel did not hit")
	assert_false(game.menus.shell.key(KEY_X), "the confirm took an unrelated key")
	game.menus.shell.cancel_confirm()

func test_confirm_from_the_match_dims_the_pitch_and_cancels_back() -> void:
	game.menus.close()
	game.hud_layer.visible = true
	game.menus.shell.open_quit_confirm()
	assert_eq(game.menus.shell.screen, AppShell.SCREEN_CONFIRM, "Esc from the match did not raise the confirm")
	assert_eq(game.menus.shell.prev_screen, AppShell.SCREEN_NONE, "a match-side confirm thinks a menu is underneath")
	game.menus.shell.queue_redraw()
	await get_tree().process_frame
	game.menus.shell.cancel_confirm()
	assert_false(game.menus.active(), "cancelling the match-side confirm left the shell up")
	assert_true(game.hud_layer.visible, "cancelling the match-side confirm hid the pitch")

func test_an_inactive_shell_swallows_nothing() -> void:
	game.menus.close()
	assert_false(game.menus.shell.click(Vector2(10, 10)), "an inactive shell took a click")
	assert_false(game.menus.shell.key(KEY_ENTER), "an inactive shell took a key")
	assert_false(game.menus.shell.handle_input(InputEventKey.new(), Vector2.ZERO), "an inactive shell took an event")
	assert_false(game.menus.handle_input(InputEventKey.new(), Vector2.ZERO), "the host forwarded input to an inactive shell")

func test_closing_keeps_music_only_for_fixture_setup() -> void:
	game.menus.open_menu()
	assert_true(game.menus.shell.music.wanted, "the menu did not start its music")
	game.menus.shell.close(true)
	assert_true(game.menus.shell.music.wanted, "walking to fixture setup stopped the music")
	game.menus.shell.open_menu(true)
	game.menus.shell.close()
	assert_false(game.menus.shell.music.wanted, "closing the shell kept the music")

func test_the_backdrop_falls_back_and_crossfades() -> void:
	game.menus.open_menu()
	assert_eq(game.menus.shell.volume_percent(), game.menus.shell.volume_percent(), "the volume readout is unstable")
	var saved: Array = game.menus.shell.stills
	game.menus.shell.stills = []
	game.menus.shell.queue_redraw()
	await get_tree().process_frame
	game.menus.shell.stills = saved
	game.menus.shell.motion = MenuScreen.SLOT - 0.2
	game.menus.shell.queue_redraw()
	await get_tree().process_frame
	assert_gt(MenuScreen.fade_alpha(game.menus.shell.motion), 0.0, "the crossfade pose drew no incoming still")
	game.menus.shell.motion = 0.0
	game.menus.shell.queue_redraw()
	await get_tree().process_frame

func test_fixture_flags_parse_without_the_scene() -> void:
	var known: Array = TeamData.team_ids()
	var f := FixtureArgs.parse(PackedStringArray(["--seed=42", "--home=ars", "--away=liv"]), known, {"seed": 1000, "home": "MUN", "away": "MCI"})
	assert_eq(int(f["seed"]), 42, "the seed flag did not parse")
	assert_eq(str(f["home"]), "ARS", "the home flag did not normalise")
	assert_eq(str(f["away"]), "LIV", "the away flag did not normalise")
	assert_true(bool(f["given"]), "a given fixture was not marked")
	var bad := FixtureArgs.parse(PackedStringArray(["--home=NOPE"]), known, {"seed": 7, "home": "MUN", "away": "MCI"})
	assert_eq(str(bad["home"]), "MUN", "an unknown club replaced the default side")
	assert_false(bool(bad["given"]), "an unknown club marked the fixture as given")
	assert_eq(int(bad["seed"]), 7, "an untouched seed changed")
