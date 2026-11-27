extends GdToolsTest


var game = null

func before_all() -> void:
	PLDatabase.cache_dir = TestScratch.dir("cache_test_render")
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)


	game.dev.ui_scale = 4.0
	game._sync_overlay_scale()
	game._on_fixture_confirmed("MUN", "MCI")
	TestBriefing.kick(game)
	game.paused = true

func after_all() -> void:
	if is_instance_valid(game):
		game.queue_free()
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _motion(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p * game.hud_scale
	ev.relative = Vector2(0, 6)
	game._input(ev)


func _move(p: Vector2) -> void:
	var ev := InputEventMouseMotion.new()
	ev.position = p * game.hud_scale
	ev.relative = Vector2(0, 0)
	game._input(ev)

func _press(p: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = p * game.hud_scale
	game._input(ev)

func _release(p: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = false
	ev.position = p * game.hud_scale
	game._input(ev)


func _click(p: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	_press(p, button)
	_release(p, button)

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = code
	game._input(ev)

func _screen() -> Control:
	return game.wiki_host.screen


func _body() -> Rect2:
	var screen := _screen()
	return Rect2(screen.body.position, screen.body.size)

func test_the_phone_sheet_is_compact_and_scrolls() -> void:
	assert_true(game.touch, "the forced phone scale should count as touch")
	game.wiki_host.open_page(WikiModel.LEAGUE, "")
	await get_tree().process_frame
	var screen := _screen()
	assert_true(screen.is_compact(), "the sheet did not read as compact")
	assert_gt(screen.body.max_scroll(), 0.0, "the league table should scroll on a phone")
	_motion(Vector2(120, 260))
	_press(Vector2(120, 260), MOUSE_BUTTON_WHEEL_DOWN)
	assert_gt(screen.body.scroll, 0.0, "the wheel did not scroll the body")
	await get_tree().process_frame
	game.wiki_host.close()

func test_every_page_kind_draws() -> void:
	for page in [[WikiModel.LEAGUE, ""], [WikiModel.TEAM, "MUN"], [WikiModel.PLAYER, "MUN-b-fernandes"], [WikiModel.PLAYER, "MUN-s-lammens"]]:
		game.wiki_host.open_page(str(page[0]), str(page[1]))
		await get_tree().process_frame
		var screen := _screen()
		assert_gt(screen.body.rows().size(), 5, "%s laid out no rows" % str(page[0]))
		screen.body.scroll_by(100000.0)
		await get_tree().process_frame
		screen.body.scroll_by(-100000.0)
		await get_tree().process_frame
		game.wiki_host.close()

func test_a_pointer_tap_opens_a_row() -> void:
	game.wiki_host.open_page(WikiModel.LEAGUE, "")
	await get_tree().process_frame
	var screen := _screen()
	var row: Dictionary = {}
	for r in screen.body.rows():
		if str(r["k"]) == "trow" and r.has("target"):
			row = r
			break
	assert_false(row.is_empty(), "the league page drew no tappable row")
	var at: Vector2 = screen.body.position + (row["rect"] as Rect2).position + Vector2(12.0, 8.0)
	_click(at)
	assert_true(game.wiki_host.is_open(), "the tap closed the sheet")
	assert_eq(game.wiki_host.screen.stack.size(), 2, "the tap did not open a page")
	_key(KEY_ESCAPE)
	assert_eq(game.wiki_host.screen.stack.size(), 1, "escape did not walk back")
	_key(KEY_ESCAPE)
	assert_false(game.wiki_host.is_open(), "escape at the root did not close the sheet")


func test_a_trackpad_pan_gesture_scrolls_the_body() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	assert_gt(screen.body.max_scroll(), 0.0, "the club page should scroll on a phone")
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0.0, 2.0)
	game._input(pan)
	assert_gt(screen.body.scroll, 0.0, "the pan gesture did not scroll the body")
	game.wiki_host.close()

func test_wheel_up_and_down_both_move_the_body() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	_press(Vector2(120.0, 260.0), MOUSE_BUTTON_WHEEL_DOWN)
	var down: float = screen.body.scroll
	assert_gt(down, 0.0, "the wheel did not scroll down")
	_press(Vector2(120.0, 260.0), MOUSE_BUTTON_WHEEL_UP)
	assert_lt(screen.body.scroll, down, "the wheel did not scroll back up")
	game.wiki_host.close()


func test_a_drag_scrolls_without_opening_a_page() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	var start := Vector2(120.0, 220.0)
	var depth: int = screen.stack.size()
	_press(start)
	_move(start - Vector2(0.0, 30.0))
	_move(start - Vector2(0.0, 60.0))
	assert_gt(screen.body.scroll, 0.0, "the drag did not scroll the body")
	_release(start - Vector2(0.0, 60.0))
	assert_true(game.wiki_host.is_open(), "the drag closed the sheet")
	assert_eq(screen.stack.size(), depth, "the drag opened a page")
	game.wiki_host.close()

func test_hover_and_a_stray_release_change_nothing() -> void:
	game.touch = false
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	_move(Vector2(120.0, 220.0))
	assert_eq(screen.body.scroll, 0.0, "hover scrolled the body")
	_release(Vector2(120.0, 220.0))
	assert_eq(screen.stack.size(), 1, "a release with no press opened a page")
	game.touch = true
	game.wiki_host.close()


func test_a_tap_after_scrolling_opens_the_row_that_is_drawn() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	var picked: Dictionary = {}
	for r in screen.body.rows():
		if str(r["k"]) == "trow" and str((r.get("target", {}) as Dictionary).get("page", "")) == "player":
			picked = r
			break
	assert_false(picked.is_empty(), "the club page drew no squad rows")


	var scroll: float = maxf(0.0, (picked["rect"] as Rect2).position.y - 80.0)
	assert_gt(scroll, 0.0, "the squad starts on screen; nothing to scroll")
	screen.body.scroll_to(scroll)
	var drawn: Vector2 = screen.body.position + (picked["rect"] as Rect2).position + Vector2(12.0, 8.0) - Vector2(0.0, scroll)
	_click(drawn)
	assert_eq(screen.stack.size(), 2, "the tap did not open the row under the pointer")
	assert_eq(str(screen.current()["id"]), str((picked["target"] as Dictionary)["id"]), "the tap opened the row from the unscrolled layout")
	game.wiki_host.close()

func test_a_tap_outside_the_sheet_is_ignored() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	var header: Vector2 = screen.body.position + Vector2(60.0, -20.0)
	_click(header)
	assert_eq(screen.stack.size(), 1, "a tap in the header opened a page")
	game.wiki_host.close()


func test_keys_scroll_and_the_last_squad_row_is_reachable() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	_key(KEY_DOWN)
	assert_gt(screen.body.scroll, 0.0, "DOWN did not scroll")
	_key(KEY_PAGEDOWN)
	assert_gt(screen.body.scroll, 120.0, "PAGE DOWN did not scroll a page")
	_key(KEY_END)
	assert_almost_eq(screen.body.scroll, screen.body.max_scroll(), 0.5, "END did not reach the end of the page")
	var squad_row := Rect2()
	for r in screen.body.rows():
		if str(r["k"]) == "trow" and str((r.get("target", {}) as Dictionary).get("page", "")) == "player":
			squad_row = r["rect"]
	assert_gt(squad_row.size.y, 0.0, "the club page drew no squad rows")
	assert_lte(squad_row.end.y - screen.body.scroll, screen.body.size.y + 0.5, "the last squad row is still below the fold")
	_key(KEY_PAGEUP)
	assert_lt(screen.body.scroll, screen.body.max_scroll(), "PAGE UP did not come back")
	_key(KEY_HOME)
	assert_eq(screen.body.scroll, 0.0, "HOME did not return to the top")
	game.wiki_host.close()

func test_a_press_and_release_on_the_back_door_closes_the_sheet() -> void:
	game.wiki_host.open_page(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var screen := _screen()
	screen.queue_redraw()
	var back := Rect2()
	for b in screen.buttons:
		if str(b["id"]) == "back":
			back = b["rect"]
	assert_gt(back.size.x, 40.0, "the sheet drew no back door")
	_click(back.position + back.size * 0.5)
	assert_false(game.wiki_host.is_open(), "a click on the back door did not close the sheet")

func test_the_picker_draws_its_league_door() -> void:
	game.open_select()
	await get_tree().process_frame
	var door := Rect2()
	for b in game.selector.buttons:
		if str(b["id"]) == "league":
			door = b["rect"]
	assert_gt(door.size.x, 40.0, "the fixture sheet has no league door")
	assert_gt(game.selector.button_at(door.position + door.size * 0.5).length(), 0, "the league door is not tappable")
	game.selector.key(KEY_L)
	assert_true(game.wiki_host.is_open(), "the picker's L key did not open the league")
	game.wiki_host.close()
	assert_true(game.select_open, "closing the sheet should return to the picker")
	game._close_select()
	game.paused = true
