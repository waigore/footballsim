extends GdToolsTest

## The match HUD's show/hide (#158): the bands slide away while the score and the
## match cards stay, one discreet door never moves, the choice survives a
## relaunch, and a phone opens already following the ball. Driven through the
## real main.gd, the same way the touch and input suites drive it.

const SIZES := [
	Vector2(1600, 900),
	Vector2(1280, 720),
	Vector2(1024, 600),
]

const COMPACT_SIZES := [
	Vector2(913, 411),
	Vector2(800, 360),
	Vector2(640, 300),
]

var PREFS := TestScratch.file("test_hud_toggle_issue158.cfg")
var game = null

func before_all() -> void:
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	game.menus.restore_hud()
	game.menus.close()
	game.hud_layer.visible = true
	game._on_fixture_confirmed("MUN", "MCI")
	# #157: the briefing comes before the sim, so kick it off.
	TestBriefing.kick(game)
	game.paused = true
	game.hud.queue_redraw()
	await get_tree().process_frame

func after_all() -> void:
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	if is_instance_valid(game):
		game.queue_free()

func after_each() -> void:
	# Every test starts with the chrome shown and the match paused, whatever the
	# one before it asked for, and with no pref file left behind.
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	if game == null:
		return
	game.menus.close()
	game.hud.set_hud_visible(true, true)
	game.paused = true
	game.hud_layer.visible = true

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._input(ev)

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

func _draw() -> void:
	game.hud.queue_redraw()
	await get_tree().process_frame

# ------------------------------------------------------------------ prefs ---

func test_the_pref_defaults_to_shown_and_round_trips() -> void:
	assert_true(Prefs.load_hud(PREFS), "a missing prefs file did not leave the HUD shown")
	assert_true(Prefs.save_hud(false, PREFS), "saving the HUD choice failed")
	assert_false(Prefs.load_hud(PREFS), "the hidden choice did not survive the file")
	assert_true(Prefs.save_hud(true, PREFS), "saving the shown choice failed")
	assert_true(Prefs.load_hud(PREFS), "the shown choice did not survive the file")

func test_the_two_prefs_live_in_one_file_without_erasing_each_other() -> void:
	assert_true(Prefs.save_bgm(0.4, PREFS), "saving the volume failed")
	assert_true(Prefs.save_hud(false, PREFS), "saving the HUD choice failed")
	assert_almost_eq(Prefs.load_bgm(PREFS), 0.4, 0.0001, "the HUD save erased the volume")
	assert_true(Prefs.save_bgm(0.9, PREFS), "re-saving the volume failed")
	assert_false(Prefs.load_hud(PREFS), "the volume save erased the HUD choice")

func test_a_wrong_value_type_falls_back_to_shown() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value(Prefs.SECTION_UI, Prefs.KEY_HUD, "yes")
	assert_eq(cfg.save(PREFS), OK, "could not write the type probe")
	assert_true(Prefs.load_hud(PREFS), "a string HUD choice did not default to shown")

# --------------------------------------------------------------- geometry ---

func test_the_toggle_never_moves_and_stays_clear_of_every_band() -> void:
	for vp in SIZES:
		var r: Rect2 = HudLayout.hud_toggle_rect(vp, false)
		assert_gte(r.size.y, HudLayout.HUD_TOGGLE_H, "the desktop pill is a hairline at %s" % vp)
		assert_false(r.intersects(HudLayout.commentary_rect(vp)), "the pill covers the ticker at %s" % vp)
		assert_false(r.intersects(HudLayout.controls_rect(vp)), "the pill covers the control bar at %s" % vp)
		assert_false(r.intersects(HudLayout.scoreboard_rect(vp)), "the pill covers the scoreboard at %s" % vp)
		assert_true(Rect2(Vector2.ZERO, vp).encloses(r), "the pill left the viewport at %s" % vp)
	for vp in COMPACT_SIZES:
		var r: Rect2 = HudLayout.hud_toggle_rect(vp, true)
		assert_gte(r.size.y, 44.0, "the phone pill is under the 44-unit tap floor at %s" % vp)
		assert_false(r.intersects(HudLayout.commentary_rect(vp)), "the phone pill covers the ticker at %s" % vp)
		assert_false(r.intersects(HudLayout.controls_rect(vp, true)), "the phone pill covers the bar at %s" % vp)
		assert_true(Rect2(Vector2.ZERO, vp).encloses(r), "the phone pill left the viewport at %s" % vp)

# ------------------------------------------------------------------ hiding ---

func test_the_chrome_slides_away_and_leaves_the_score_and_the_toggle() -> void:
	var vp: Vector2 = game.hud.design_vp()
	game.hud.toggle_hud()
	assert_false(game.hud.hud_visible, "the toggle did not record the choice")
	game.hud._process(0.11)
	assert_between(game.hud.slide, 0.4, 0.6, "half the glide did not leave the bands halfway")
	game.hud._process(0.60)
	assert_almost_eq(game.hud.slide, 0.0, 0.001, "the bands never finished sliding away")
	await _draw()
	assert_eq(_door("league"), Rect2(), "a hidden band kept its league door")
	assert_eq(_door("pause"), Rect2(), "a hidden band kept its pause door")
	assert_eq(_door("hud"), HudLayout.hud_toggle_rect(vp, game.hud.touch), "the pill is not the one door left")
	assert_ne(_door("team_0"), Rect2(), "the scoreboard stopped being a door")
	assert_eq(game.hud.button_at(HudLayout.controls_rect(vp, game.hud.touch).get_center()), "",
		"a hidden control bar still answered a press")

func test_the_sim_keeps_running_while_the_hud_is_hidden() -> void:
	game.hud.set_hud_visible(false)
	game.hud._process(1.0)
	game.paused = false
	var before: float = game.engine.clock
	game._process(0.05)
	assert_gt(game.engine.clock, before, "the match stopped ticking while the chrome was hidden")

func test_the_keyboard_and_the_pill_toggle_the_same_state() -> void:
	game.hud.set_hud_visible(true, true)
	_key(KEY_U)
	assert_false(game.hud.hud_visible, "U did not hide the chrome")
	_key(KEY_U)
	assert_true(game.hud.hud_visible, "U did not bring the chrome back")
	await _draw()
	_tap(HudLayout.hud_toggle_rect(game.hud.design_vp(), game.hud.touch).get_center())
	assert_false(game.hud.hud_visible, "the pill did not hide the chrome")
	game.hud._process(1.0)
	await _draw()
	assert_ne(_door("hud"), Rect2(), "the pill vanished with the chrome")
	_tap(HudLayout.hud_toggle_rect(game.hud.design_vp(), game.hud.touch).get_center())
	assert_true(game.hud.hud_visible, "the pill did not bring the chrome back")

# ---------------------------------------------------------------- settings ---

func test_the_settings_switch_reads_and_writes_the_same_pref() -> void:
	game.menus.open_settings()
	var shell = game.menus.shell
	assert_true(shell.hud_visible, "the settings sheet did not read the shown default")
	var r: Rect2 = SettingsScreen.hud_toggle_rect(shell.design_vp())
	assert_gte(r.size.y, 44.0, "the HUD switch is too short to tap")
	assert_true(shell.button_at(r.get_center()) == "hud", "the switch did not answer a press")
	shell.click(r.get_center())
	assert_false(shell.hud_visible, "the switch did not turn the HUD off")
	assert_false(Prefs.load_hud(PREFS), "the switch did not save the choice")
	assert_false(game.hud.hud_visible, "the match did not follow the settings switch")
	assert_almost_eq(game.hud.slide, 0.0, 0.001, "a switch under the shell animated the hidden overlay")
	shell.click(r.get_center())
	assert_true(shell.hud_visible, "the switch did not turn the HUD back on")
	assert_true(Prefs.load_hud(PREFS), "turning it back on did not save the choice")

func test_the_settings_card_holds_both_rows() -> void:
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var card: Rect2 = SettingsScreen.card_rect(vp)
		assert_true(card.encloses(SettingsScreen.hud_toggle_rect(vp)), "the HUD switch left the card at %s" % vp)
		assert_true(card.encloses(SettingsScreen.track_rect(vp)), "the volume track left the card at %s" % vp)
		assert_false(SettingsScreen.hud_toggle_rect(vp).intersects(SettingsScreen.track_rect(vp)),
			"the two rows overlap at %s" % vp)

func test_a_saved_choice_is_restored_without_animating() -> void:
	assert_true(Prefs.save_hud(false, PREFS), "could not write the saved choice")
	game.hud.set_hud_visible(true, true)
	game.menus.restore_hud()
	assert_false(game.hud.hud_visible, "the saved hidden choice was not restored")
	assert_almost_eq(game.hud.slide, 0.0, 0.001, "the restore animated instead of starting hidden")
	assert_true(Prefs.save_hud(true, PREFS), "could not write the shown choice")
	game.menus.restore_hud()
	assert_true(game.hud.hud_visible, "the saved shown choice was not restored")
	assert_almost_eq(game.hud.slide, 1.0, 0.001, "the restore animated instead of starting shown")

# ------------------------------------------------------------------ camera ---

func test_a_phone_opens_in_follow_and_the_desktop_stays_wide() -> void:
	assert_eq(MatchView.default_follow(), OS.has_feature("mobile"),
		"the opening camera is not the platform rule")
	assert_false(game.camera_follow, "a desktop match opened tracking the ball instead of wide")
