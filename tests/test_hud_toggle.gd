extends GdToolsTest


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
	game._on_fixture_confirmed("ENG-MUN1", "ENG-MCI1")

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


func test_the_settings_switch_reads_and_writes_the_same_pref() -> void:
	game.menus.open_settings()
	var shell = game.menus.shell
	assert_true(shell.hud_visible, "the settings sheet did not read the shown default")
	var r: Rect2 = SettingsLayout.hud_toggle_rect(shell.design_vp())
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
		var card: Rect2 = SettingsLayout.card_rect(vp)
		assert_true(card.encloses(SettingsLayout.hud_toggle_rect(vp)), "the HUD switch left the card at %s" % vp)
		assert_true(card.encloses(SettingsLayout.track_rect(vp)), "the volume track left the card at %s" % vp)
		assert_false(SettingsLayout.hud_toggle_rect(vp).intersects(SettingsLayout.track_rect(vp)),
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


func test_a_phone_opens_in_follow_and_the_desktop_stays_wide() -> void:
	assert_eq(MatchView.default_follow(), OS.has_feature("mobile"),
		"the opening camera is not the platform rule")
	assert_false(game.camera_follow, "a desktop match opened tracking the ball instead of wide")


func test_the_match_hud_row_says_what_on_means() -> void:


	var hint: String = SettingsScreen.HUD_ROW_HINT
	assert_true(hint.begins_with("ON "), "the caption does not name the ON state: %s" % hint)
	assert_true(hint.contains("SHOWS"), "the caption does not say the bars show: %s" % hint)
	assert_false(hint.contains("HIDES"), "the caption still reads as the OFF state: %s" % hint)

func test_a_hidden_hud_plays_again_from_the_full_time_card() -> void:
	game.touch = true
	game.hud.touch = true
	var vp: Vector2 = game.hud.design_vp()
	game.engine.phase = "full_time"
	game.result_hold = false
	game.hud.set_hud_visible(false, true)
	await _draw()
	var card: Rect2 = HudLayout.break_metrics(vp, 0, 0)["rect"]
	assert_eq(_door("restart"), card, "a hidden chrome left the full-time card undoorable")
	var before = game.engine
	_tap(card.get_center())
	assert_ne(game.engine, before, "tapping the full-time card did not play again")
	game.hud.set_hud_visible(true, true)

class LabelSurface extends HudChrome:
	var texts: Array = []

	func text(c: CanvasItem, pos: Vector2, s: String, size: int, color: Color, font: Font, outline: int = 0, outline_col: Color = Color(0, 0, 0, 0.5)) -> void:
		texts.append({"s": s, "pos": pos, "size": size, "color": color})

func _paint_through(surface: HudChrome) -> void:
	var shipped: HudChrome = game.hud.chrome
	game.hud.chrome = surface
	game.hud.queue_redraw()
	await get_tree().process_frame
	game.hud.chrome = shipped

func _assert_pitch_numbers(surface: LabelSurface, when: String) -> void:
	var p := HudPaint.new(game.hud.chrome, game.hud.design_vp())
	var vp: Vector2 = game.hud.design_vp()
	var checked := 0
	for pl in game.engine.players:
		if pl.sent_off:
			continue
		var sp: Vector2 = game.hud.roster_band.w2s(p, game.hud, pl.pos - Vector2(0, pl.z * 0.55))
		if sp.x < -40.0 or sp.x > vp.x + 40.0 or sp.y < -40.0 or sp.y > vp.y + 40.0:
			continue
		var at_token := false
		for t in surface.texts:
			if str(t["s"]) != str(pl.number):
				continue
			var pos: Vector2 = t["pos"]
			if absf(pos.x - sp.x) > 24.0 or absf(pos.y - sp.y) > 14.0:
				continue
			assert_gte(float((t["color"] as Color).a), 0.9, "%s: a shirt number painted faded" % when)
			at_token = true
			break
		assert_true(at_token, "%s: the #%d shirt number left the pitch" % [when, pl.number])
		checked += 1
	assert_gt(checked, 0, "%s: no player token was in the frame to label" % when)

func test_a_hidden_hud_keeps_the_shirt_numbers_and_surnames() -> void:
	game.hud.set_hud_visible(false, true)
	assert_almost_eq(game.hud.slide, 0.0, 0.001, "the hidden HUD was not fully off")
	var labelled = null
	for pl in game.engine.players:
		if not pl.sent_off and pl.id != game.focus_id:
			labelled = pl
			break
	assert_not_null(labelled, "the fixture had no player to label")
	game.engine.ball.pos = labelled.pos
	var surface := LabelSurface.new()
	await _paint_through(surface)
	assert_true(game.hud_layer.visible, "hiding the chrome hid the whole pitch overlay")
	_assert_pitch_numbers(surface, "HUD hidden")
	var surnames := 0
	for t in surface.texts:
		if str(t["s"]) == labelled.surname_text():
			surnames += 1
	assert_gt(surnames, 0, "a near-ball surname left the pitch with the HUD")
	game.hud.set_hud_visible(true, true)

func test_the_pitch_labels_do_not_fade_with_the_bands() -> void:
	game.hud.set_hud_visible(false, true)
	game.hud.slide = 0.5
	var surface := LabelSurface.new()
	await _paint_through(surface)
	_assert_pitch_numbers(surface, "HUD half-slid")
	game.hud.set_hud_visible(true, true)

