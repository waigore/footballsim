extends GdToolsTest

## The play scene driven the way a phone drives it: the overlay hit-tests in
## design space, a tap on a token opens its card, and the fixture sheet has a
## way out that does not need an Escape key.

var game = null

func before_all() -> void:
	# Loaded by path rather than through the scene's ext_resource: coverage
	# instrumentation only sees the script a test loads itself.
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	# Force the handheld overlay, landing the design height on a phone's, so the
	# point-to-design conversion is exercised rather than the identity. The test
	# viewport is square, so the scale comes from its height.
	game.dev.ui_scale = game.get_viewport_rect().size.y / 411.0
	game._sync_overlay_scale()
	game._on_fixture_confirmed("MUN", "MCI")
	game.paused = true

func after_all() -> void:
	if is_instance_valid(game):
		game.queue_free()

func _tap(design_point: Vector2) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = design_point * game.hud_scale
	game._input(ev)

func _door(id: String) -> Rect2:
	for b in game.hud.buttons:
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func test_the_phone_overlay_is_scaled_and_compact() -> void:
	assert_gt(game.hud_scale, 1.5, "the forced phone scale was not applied")
	assert_true(game.touch, "a forced phone scale should count as touch")
	var vp: Vector2 = game.hud.design_vp()
	assert_true(HudLayout.is_compact(vp), "design viewport is not phone shaped: %s" % vp)
	assert_almost_eq(vp.y, 411.0, 1.0, "the design height is not a phone's")
	assert_almost_eq(game.hud_layer.transform.get_scale().x, game.hud_scale, 0.01, "the overlay layer is not scaled")

func test_a_tap_hits_a_bar_door_in_design_space() -> void:
	var door := _door("pause")
	assert_gt(door.size.x, 44.0, "the pause door is too small to tap")
	var was: bool = game.paused
	_tap(door.position + door.size * 0.5)
	assert_ne(game.paused, was, "tapping the pause door did not change the run state")
	_tap(door.position + door.size * 0.5)

func test_a_tap_on_a_token_opens_that_players_card() -> void:
	var p = game.engine.players[3]
	var screen: Vector2 = game.get_viewport().get_canvas_transform() * p.pos
	_tap(screen / game.hud_scale)
	assert_eq(game.focus_id, p.id, "the tap did not focus the token under the finger")
	assert_eq(game.actors.focus_id, p.id, "the view layer did not follow the focus")

func test_a_tap_on_empty_pitch_clears_the_focus() -> void:
	game.focus_id = game.engine.players[1].id
	game.actors.focus_id = game.focus_id
	var band: Rect2 = HudLayout.pitch_band(game.hud.design_vp())
	_tap(Vector2(band.position.x + 8.0, band.position.y + band.size.y * 0.5))
	assert_eq(game.focus_id, -1, "the focus survived a tap on empty grass")

func test_the_teams_door_opens_the_sheet_and_back_closes_it() -> void:
	var door := _door("teams")
	assert_gt(door.size.x, 0.0, "the phone bar has no teams door")
	_tap(door.position + door.size * 0.5)
	assert_true(game.select_open, "the teams door did not open the fixture sheet")
	# Draw the sheet once: its rows and its back door are built in _draw.
	game.selector.queue_redraw()
	await get_tree().process_frame
	assert_gt(game.selector.buttons.size(), 4, "the sheet drew no doors")
	var svp: Vector2 = game.selector.design_vp()
	var back: Rect2 = game.selector.back_rect(svp)
	assert_gte(back.size.y, 44.0, "the back door is too small to tap")
	assert_lte(back.end.x, svp.x, "the back door runs off the sheet")
	game.selector.click("back")
	assert_false(game.select_open, "back did not close the sheet")

func test_the_size_change_notification_re_fits_the_overlay() -> void:
	game._notification(Node.NOTIFICATION_WM_SIZE_CHANGED)
	assert_gt(game.hud_scale, 1.5, "a resize dropped the forced phone scale")
	assert_gt(game.base_zoom, 0.0, "the camera fit collapsed")

func test_dev_flags_are_parsed_without_a_command_line() -> void:
	var cap := DevCapture.new()
	cap.parse(game, ["--shots=1,2.5", "--quit=9", "--focus=4", "--clock=2760", "--hover=2", "--ui-scale=2.19", "--managers", "--full"])
	assert_eq(cap.shot_times.size(), 2, "the shots list did not parse")
	assert_almost_eq(cap.quit_after, 9.0, 0.01, "the quit time did not parse")
	assert_eq(cap.hover_force, 2, "the hover pin did not parse")
	assert_almost_eq(cap.ui_scale, 2.19, 0.01, "the ui-scale override did not parse")
	assert_eq(game.mode, "full", "--full did not select the full match")
	assert_eq(game.focus_id, 4, "--focus did not take")

func test_dev_hover_pin_moves_the_overlay_pointer() -> void:
	var target = null
	for p in game.engine.players:
		if game.engine.by_id.has(p.id):
			target = p
			break
	assert_not_null(target, "no player left on the pitch to pin")
	var cap := DevCapture.new()
	cap.hover_force = target.id
	assert_true(cap.apply_hover(game), "the hover pin reported nothing to do")
	assert_eq(game.hover_id, target.id, "the pinned hover did not reach the game")
	assert_eq(game.actors.hover_id, target.id, "the view layer did not follow the pinned hover")
	var screen: Vector2 = game.get_viewport().get_canvas_transform() * target.pos
	assert_almost_eq(game.hud.mouse.x, (screen.x + 24.0) / game.hud_scale, 0.5, "the pinned pointer is not in design space")
	var idle := DevCapture.new()
	assert_false(idle.apply_hover(game), "an unpinned hover should do nothing")

func test_dev_capture_writes_a_due_shot() -> void:
	var cap := DevCapture.new()
	cap.shot_times = [0.0]
	cap.tick(game, 0.5)
	assert_eq(cap.shot_index, 1, "the due shot did not fire")
	var path := ProjectSettings.globalize_path("res://shots/shot_00.png")
	if FileAccess.file_exists(path):
		assert_gt(FileAccess.get_file_as_bytes(path).size(), 0, "an empty PNG was written")
		DirAccess.remove_absolute(path)
	var idle := DevCapture.new()
	idle.tick(game, 6.0)
	assert_almost_eq(idle.elapsed, 6.0, 0.01, "the harness clock does not advance")

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._input(ev)

func test_key_bindings_cover_every_arm() -> void:
	game.paused = false
	_key(KEY_SPACE)
	assert_true(game.paused, "space did not pause")
	_key(KEY_1)
	assert_almost_eq(game.speed, 1.0, 0.01, "1x not selected")
	_key(KEY_2)
	assert_almost_eq(game.speed, 2.0, 0.01, "2x not selected")
	_key(KEY_3)
	assert_almost_eq(game.speed, 4.0, 0.01, "4x not selected")
	_key(KEY_4)
	assert_almost_eq(game.speed, 8.0, 0.01, "8x not selected")
	game.mode = "highlights"
	_key(KEY_H)
	assert_eq(game.mode, "full", "H did not switch to the full match")
	_key(KEY_H)
	assert_eq(game.mode, "highlights", "H did not switch back to highlights")
	_key(KEY_C)
	assert_true(game.camera_follow, "C did not follow the ball")
	_key(KEY_C)
	assert_false(game.camera_follow, "C did not return to the wide view")
	game.names_visible = true
	_key(KEY_N)
	assert_false(game.names_visible, "N did not hide the names")
	_key(KEY_S)
	_key(KEY_R)
	game.focus_id = 3
	_key(KEY_ESCAPE)
	assert_eq(game.focus_id, -1, "escape did not clear the tracked player")

func test_sheet_key_bindings_cover_every_arm() -> void:
	game.open_select()
	var sheet = game.selector
	var home: int = sheet.home_idx
	sheet.key(KEY_RIGHT)
	assert_ne(sheet.home_idx, home, "right did not cycle the home club")
	sheet.key(KEY_LEFT)
	sheet.key(KEY_DOWN)
	sheet.key(KEY_UP)
	sheet.key(KEY_TAB)
	sheet.key(KEY_KP_ENTER)
	assert_false(game.select_open, "enter did not kick off")
	game.open_select()
	assert_false(sheet.key(KEY_F1), "an unbound key should report unhandled")
	sheet.key(KEY_ESCAPE)
	assert_false(game.select_open, "escape did not close the sheet")

func test_dev_flags_cover_the_rest_of_the_table() -> void:
	var cap := DevCapture.new()
	cap.parse(game, ["--follow", "--paused", "--fakegoal"])
	assert_true(game.camera_follow, "--follow did not follow the ball")
	assert_true(game.paused, "--paused did not pause")
	assert_eq(game.engine.phase, "goal", "--fakegoal did not stage a goal")
	assert_false(game.engine.last_goal.is_empty(), "--fakegoal left no scorer")
