extends GdToolsTest

## Every door into the encyclopedia, driven through main.gd: the fixture sheet,
## the in-match control bar, the scoreboard club chrome and the tracked player
## card — plus the full-time hook that writes the match into the seed.

var game = null

func before_all() -> void:
	PLDatabase.cache_dir = TestScratch.dir("cache_test_entry")
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.dev.ui_scale = game.get_viewport_rect().size.y / 411.0
	game._sync_overlay_scale()
	game._on_fixture_confirmed("MUN", "MCI")
	game.paused = true

func after_all() -> void:
	if is_instance_valid(game):
		game.queue_free()
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

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

func test_the_bar_opens_the_league_and_back_returns_to_the_match() -> void:
	var door := _door("league")
	assert_gt(door.size.x, 20.0, "the league door is not on the bar")
	_tap(door.position + door.size * 0.5)
	assert_true(game.wiki_host.is_open(), "the league door did not open the encyclopedia")
	assert_eq(str(game.wiki_host.screen.current()["page"]), "league", "the league door opened the wrong page")
	assert_false(game.hud_layer.visible, "the broadcast stayed visible under the sheet")
	assert_true(game.paused, "the match did not pause under the sheet")
	var back := Rect2()
	game.wiki_host.screen.queue_redraw()
	for b in game.wiki_host.screen.buttons:
		if str(b["id"]) == "back":
			back = b["rect"]
	game.wiki_host.screen.click("back")
	assert_false(game.wiki_host.is_open(), "back did not close the encyclopedia")
	assert_true(game.hud_layer.visible, "the broadcast did not come back")
	assert_true(game.paused, "closing the sheet resumed a paused match")

func test_the_scoreboard_club_chrome_opens_the_club() -> void:
	var door := _door("team_0")
	assert_gt(door.size.x, 40.0, "the home club chrome is not tappable")
	_tap(door.position + door.size * 0.5)
	assert_true(game.wiki_host.is_open(), "the club chrome did not open a page")
	assert_eq(str(game.wiki_host.screen.current()["page"]), "team", "the club chrome opened the wrong page")
	assert_eq(str(game.wiki_host.screen.current()["id"]), "MUN", "the club chrome opened the wrong club")
	game.wiki_host.close()
	await get_tree().process_frame
	_tap(_door("team_1").position + _door("team_1").size * 0.5)
	assert_eq(str(game.wiki_host.screen.current()["id"]), "MCI", "the away club chrome opened the wrong club")
	game.wiki_host.close()

func test_the_tracked_player_card_opens_the_profile() -> void:
	game.focus_id = game.engine.players[0].id
	game.actors.focus_id = game.focus_id
	game.hud.queue_redraw()
	await get_tree().process_frame
	var door := _door("profile")
	assert_gt(door.size.x, 20.0, "the player card has no profile door")
	_tap(door.position + door.size * 0.5)
	assert_true(game.wiki_host.is_open(), "the profile door did not open the encyclopedia")
	assert_eq(str(game.wiki_host.screen.current()["page"]), "player", "the profile door opened the wrong page")
	assert_eq(str(game.wiki_host.screen.current()["id"]), str(game.engine.players[0].key), "the profile opened another player")
	game.wiki_host.close()
	game.focus_id = -1
	game.actors.focus_id = -1

func test_the_fixture_sheet_has_its_own_league_door() -> void:
	game.open_select()
	assert_true(game.select_open, "the fixture sheet did not open")
	game.selector.click("league")
	assert_true(game.wiki_host.is_open(), "the picker's league door did not open the encyclopedia")
	assert_false(game.sel_layer.visible, "the picker stayed painted under the sheet")
	game.wiki_host.close()
	assert_true(game.select_open, "closing the sheet should return to the picker")
	assert_true(game.sel_layer.visible, "the picker did not come back")
	assert_true(game.paused, "returning to the picker must stay paused")
	game._close_select()
	game.paused = true

func test_a_finished_match_is_written_to_the_seed_once() -> void:
	game.new_match(4242)
	game.paused = true
	game.engine.phase = "full_time"
	game._process(0.016)
	assert_true(game.result_recorded, "full time did not record the result")
	var club := PLRepository.shared().sim_club("MUN")
	assert_eq(int(club.get("played", 0)), 1, "the club record did not land")
	var lines := 0
	for p in game.engine.players:
		if int(PLRepository.shared().sim_player(str(p.key)).get("apps", 0)) == 1:
			lines += 1
	assert_eq(lines, game.engine.players.size(), "not every player made the ledger")
	game._process(0.016)
	assert_eq(int(PLRepository.shared().sim_club("MUN").get("played", 0)), 1, "full time recorded the match twice")
	PLSimStats.clear()
