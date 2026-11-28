extends GdToolsTest


const REF := Vector2(1600, 900)

var game = null

func before_all() -> void:
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	await get_tree().process_frame

func after_all() -> void:
	if is_instance_valid(game):
		game.queue_free()


func test_the_scale_has_a_comfortable_floor() -> void:


	assert_almost_eq(ChromeDensity.scale_for(Vector2(1280, 720)), ChromeDensity.BASE, 0.001,
		"a short window dropped below the reading base")
	assert_almost_eq(ChromeDensity.scale_for(Vector2(1512, 824)), ChromeDensity.BASE, 0.001,
		"a 14-inch fullscreen dropped below the reading base")
	assert_gte(ChromeDensity.scale_for(Vector2(640, 360)), ChromeDensity.BASE,
		"a tiny window shrank the chrome")

func test_the_scale_is_one_design_unit_per_reading_point() -> void:
	var s := ChromeDensity.scale_for(REF)
	assert_almost_eq(s, ChromeDensity.BASE, 0.001, "the reference window lost its base scale")


	assert_gte(10.0 * s, 12.0, "a 10-unit caption is still too small")

func test_the_scale_grows_with_the_window() -> void:
	var ref := ChromeDensity.scale_for(REF)
	var tall := ChromeDensity.scale_for(Vector2(1920, 1080))
	assert_gt(tall, ref, "a taller window did not enlarge the chrome")
	assert_almost_eq(tall, 1.5, 0.001, "1080 points of window should read 1.5 units per point")
	assert_gt(ChromeDensity.scale_for(Vector2(2560, 1440)), tall,
		"a very tall window did not keep growing")

func test_the_scale_is_monotonic_and_capped() -> void:
	var prev := 0.0
	for h in [360.0, 600.0, 720.0, 900.0, 1080.0, 1440.0, 2160.0]:
		var s := ChromeDensity.scale_for(Vector2(h * 16.0 / 9.0, h))
		assert_gte(s, prev, "the scale fell as the window grew to %s" % h)
		assert_lte(s, ChromeDensity.MAX, "the scale left its range at %s" % h)
		prev = s
	assert_almost_eq(ChromeDensity.scale_for(Vector2(6000, 4000)), ChromeDensity.MAX, 0.001,
		"a huge window should clamp at the cap")

func test_the_scale_clamps_a_zero_window() -> void:
	assert_almost_eq(ChromeDensity.scale_for(Vector2.ZERO), ChromeDensity.BASE, 0.001,
		"a zero window should floor, not divide")


func test_the_menu_sheet_reads_at_the_chrome_scale() -> void:
	game.menus.open_menu()
	var shell = game.menus.shell
	assert_almost_eq(shell.ui_scale, game.chrome_scale, 0.001,
		"the menu shell did not take the shared chrome scale")
	var layer_scale: float = game.menus.layer.transform.get_scale().y
	assert_almost_eq(layer_scale, game.chrome_scale, 0.01,
		"the menu layer is not scaled by the chrome scale")
	var viewport_h: float = shell.get_viewport().get_visible_rect().size.y
	assert_almost_eq(shell.design_vp().y, viewport_h / game.chrome_scale, 1.0,
		"the menu design space does not shrink by the chrome scale")

func test_the_match_overlay_keeps_its_own_scale() -> void:

	assert_almost_eq(game.hud.ui_scale, game.hud_scale, 0.001,
		"the match HUD took the chrome scale")
	assert_almost_eq(game.hud_layer.transform.get_scale().y, game.hud_scale, 0.01,
		"the match HUD layer was rescaled by the chrome path")
	if not game.touch:
		assert_lt(game.hud_scale, game.chrome_scale,
			"a desktop window should keep the HUD flat and the chrome readable")

func test_the_league_and_encyclopedia_layers_read_at_the_chrome_scale() -> void:
	game.menus.league.open_wizard()
	var league = game.menus.league
	assert_almost_eq(league.screen.ui_scale, game.chrome_scale, 0.001,
		"the league sheet did not take the chrome scale")
	assert_almost_eq(league.layer.transform.get_scale().y, game.chrome_scale, 0.01,
		"the league layer is not scaled by the chrome scale")
	game.menus.league.close()
	game.wiki_host.open_page(WikiModel.LEAGUE, "")
	assert_almost_eq(game.wiki_host.screen.ui_scale, game.chrome_scale, 0.001,
		"the encyclopedia did not take the chrome scale")
	assert_almost_eq(game.wiki_host.layer.transform.get_scale().y, game.chrome_scale, 0.01,
		"the encyclopedia layer is not scaled by the chrome scale")
	game.wiki_host.close()

func test_the_fixture_sheet_reads_at_the_chrome_scale() -> void:
	game.open_select(true)
	assert_almost_eq(game.selector.ui_scale, game.chrome_scale, 0.001,
		"the fixture picker did not take the chrome scale")
	assert_almost_eq(game.sel_layer.transform.get_scale().y, game.chrome_scale, 0.01,
		"the fixture picker layer is not scaled by the chrome scale")
	game._close_select()

func test_the_handset_override_still_wins() -> void:


	game.dev.ui_scale = 2.19
	game._sync_overlay_scale()
	assert_almost_eq(game.hud_scale, 2.19, 0.001, "the forced phone scale was not applied")
	assert_almost_eq(game.chrome_scale, 2.19, 0.01, "the chrome scale did not follow the phone pose")
	game.dev.ui_scale = 0.0
	game._sync_overlay_scale()
	assert_almost_eq(game.chrome_scale, maxf(game.hud_scale, ChromeDensity.non_match_scale()), 0.001,
		"the desktop chrome scale did not come back")


func test_the_reading_floor_is_ten_design_units() -> void:


	assert_eq(ChromeDensity.MIN_READ, 10, "the non-match caption floor moved")

func test_a_sub_floor_caption_is_painted_at_the_floor() -> void:
	for size in [1, 6, 7, 8, 9]:
		assert_eq(ChromeDensity.read_size(size), ChromeDensity.MIN_READ,
			"a %d-unit caption would still paint at %d units" % [size, size])
	for size in [10, 11, 13, 22, 54]:
		assert_eq(ChromeDensity.read_size(size), size, "a %d-unit caption was shrunk" % size)

func test_every_paint_primitive_lifts_a_sub_floor_caption() -> void:


	var bold: Font = UiChrome.fonts()["bold"]
	assert_almost_eq(UiChrome.text_width(bold, "10/10", 7), UiChrome.text_width(bold, "10/10", 10),
		0.01, "UiChrome measured a lifted caption at its hairline size")
	assert_gt(UiChrome.text_width(bold, "10/10", 13), UiChrome.text_width(bold, "10/10", 10),
		"a comfortable caption was shrunk to the floor")
	assert_eq(WikiChrome.text_size(8), ChromeDensity.MIN_READ,
		"the encyclopedia kept a sub-floor caption")

func test_a_date_strip_still_covers_the_lifted_caption() -> void:


	var bold: Font = UiChrome.fonts()["bold"]
	var strip := DateHints.strip(bold, "SAT", Vector2(10.0, 40.0), 9)
	assert_gte(strip.size.y, float(ChromeDensity.MIN_READ),
		"a hover strip is shorter than the caption it explains")
	assert_almost_eq(strip.size.x, DateHints.width(bold, "SAT", 10), 0.01,
		"a hover strip is narrower than the caption it explains")


func test_a_menu_door_is_tappable_in_window_space() -> void:

	game.menus.open_menu()
	var shell = game.menus.shell
	var door := Rect2()
	for b in MenuScreen.door_rects(shell.design_vp(), false):
		if str(b["id"]) == "settings":
			door = b["rect"]
	assert_gt(door.size.x, 0.0, "the settings door is missing")
	var at: Vector2 = door.get_center() * shell.ui_scale
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	game._input(down)
	assert_eq(shell.screen, AppShell.SCREEN_SETTINGS, "a window-space click missed the settings door")


func test_the_tap_floor_lifts_a_small_control_only_on_touch() -> void:
	assert_almost_eq(UiChrome.tap_h(24.0, false), 24.0, 0.001, "a mouse grew a control")
	assert_almost_eq(UiChrome.tap_h(24.0, true), UiChrome.TAP_H, 0.001,
		"a finger kept a control below the tap floor")
	assert_almost_eq(UiChrome.tap_h(52.0, true), 52.0, 0.001,
		"a door already over the floor was shrunk to it")
