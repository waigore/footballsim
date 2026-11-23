extends GdToolsTest

## Rendering and pointer plumbing for the encyclopedia: every block kind is
## drawn at least once, the body scrolls, and the host converts pointers into
## design space for taps, buttons, wheels and keys.

var game = null

func before_all() -> void:
	PLDatabase.cache_dir = "user://cache_test_render"
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	# A phone-sized design space: compact layout, two-column kv, wrapping chips
	# and a body shorter than its content, so scrolling is real.
	game.dev.ui_scale = 4.0
	game._sync_overlay_scale()
	game._on_fixture_confirmed("MUN", "MCI")
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

func _press(p: Vector2, button: int = MOUSE_BUTTON_LEFT) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	ev.pressed = true
	ev.position = p * game.hud_scale
	game._input(ev)

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.keycode = code
	game._input(ev)

func _screen() -> Control:
	return game.wiki_host.screen

func test_the_phone_sheet_is_compact_and_scrolls() -> void:
	assert_true(game.touch, "the forced phone scale should count as touch")
	game.open_wiki(WikiModel.LEAGUE, "")
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
		game.open_wiki(str(page[0]), str(page[1]))
		await get_tree().process_frame
		var screen := _screen()
		assert_gt(screen.body.rows().size(), 5, "%s laid out no rows" % str(page[0]))
		screen.body.scroll_by(100000.0)
		await get_tree().process_frame
		screen.body.scroll_by(-100000.0)
		await get_tree().process_frame
		game.wiki_host.close()

func test_a_pointer_tap_opens_a_row() -> void:
	game.open_wiki(WikiModel.LEAGUE, "")
	await get_tree().process_frame
	var screen := _screen()
	var row: Dictionary = {}
	for r in screen.body.rows():
		if str(r["k"]) == "trow" and r.has("target"):
			row = r
			break
	assert_false(row.is_empty(), "the league page drew no tappable row")
	var at: Vector2 = screen.body.position + (row["rect"] as Rect2).position + Vector2(12.0, 8.0)
	_press(at)
	assert_true(game.wiki_host.is_open(), "the tap closed the sheet")
	assert_eq(game.wiki_host.screen.stack.size(), 2, "the tap did not open a page")
	_key(KEY_ESCAPE)
	assert_eq(game.wiki_host.screen.stack.size(), 1, "escape did not walk back")
	_key(KEY_ESCAPE)
	assert_false(game.wiki_host.is_open(), "escape at the root did not close the sheet")

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
