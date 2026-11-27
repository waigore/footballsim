extends GdToolsTest


var PREFS := TestScratch.file("test_match_mode_issue164.cfg")
var game = null
var engine_dirty := false

func before_all() -> void:
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	game.menus.restore_mode()
	game.menus.close()
	game.hud_layer.visible = true
	game._on_fixture_confirmed("MUN", "MCI")

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
	game.view.set_mode(Prefs.DEFAULT_MODE)
	game.skip_armed = false
	if game.engine != null and str(game.engine.phase) != "play":
		engine_dirty = true
	if engine_dirty:
		game.new_match(1000)
		engine_dirty = false
	game.menus.close()
	game.paused = true
	game.hud_layer.visible = true
	game.in_highlight = false
	game.fast_mode = true
	game.speed = 1.0
	game.replay = null
	game.highlight_until = -1.0

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._input(ev)

func _door(id: String) -> Rect2:
	for b in game.hud.buttons:
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func _tap_door(id: String) -> void:
	var r := _door(id)
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = (r.position + r.size * 0.5) * game.hud_scale
	game._input(ev)

func _band_label(id: String) -> String:
	var p := HudPaint.new(game.hud.chrome, game.hud.design_vp())
	for spec in game.hud.controls_band.control_specs(p, game, game.touch):
		if str(spec[0]) == id:
			return str(spec[1])
	return ""

func _vps() -> Array:
	return [Vector2(1600, 900), Vector2(1280, 720), Vector2(913, 411), Vector2(800, 360), Vector2(415, 923)]


func test_a_missing_file_opens_in_highlights() -> void:
	assert_false(FileAccess.file_exists(PREFS), "the probe file should start absent")
	assert_eq(Prefs.load_mode(PREFS), "highlights", "a missing prefs file did not default to Highlights")
	assert_eq(Prefs.mode_label(Prefs.load_mode(PREFS)), "HIGHLIGHTS", "the default view has no name")

func test_every_view_survives_a_save_and_load() -> void:
	for mode in Prefs.MODES:
		assert_true(Prefs.save_mode(str(mode), PREFS), "saving %s failed" % mode)
		assert_eq(Prefs.load_mode(PREFS), str(mode), "%s did not load back" % mode)

func test_an_unknown_or_mistyped_view_opens_in_highlights() -> void:
	assert_true(Prefs.save_mode("documentary", PREFS), "the save guarded an unknown view")
	assert_eq(Prefs.load_mode(PREFS), "highlights", "an unknown view was stored instead of defaulting")
	var cfg := ConfigFile.new()
	cfg.set_value(Prefs.SECTION_UI, Prefs.KEY_MODE, 3)
	assert_eq(cfg.save(PREFS), OK, "could not write the type probe")
	assert_eq(Prefs.load_mode(PREFS), "highlights", "a number read as a match view")

func test_the_door_cycles_three_views_and_names_each() -> void:
	assert_eq(Prefs.next_mode("highlights"), "goals", "Highlights did not lead to Goals only")
	assert_eq(Prefs.next_mode("goals"), "full", "Goals only did not lead to the full match")
	assert_eq(Prefs.next_mode("full"), "highlights", "the full match did not lead back to Highlights")
	assert_eq(Prefs.mode_label("goals"), "GOALS ONLY", "Goals only has the wrong name")
	assert_eq(Prefs.mode_label("full"), "FULL MATCH", "the full match has the wrong name")
	assert_eq(Prefs.mode_label("nonsense"), "HIGHLIGHTS", "an unknown view borrowed no name")

func test_the_view_shares_the_file_with_the_other_two_prefs() -> void:
	assert_true(Prefs.save_bgm(0.4, PREFS), "saving the volume failed")
	assert_true(Prefs.save_hud(false, PREFS), "saving the HUD choice failed")
	assert_true(Prefs.save_mode("goals", PREFS), "saving the view failed")
	assert_almost_eq(Prefs.load_bgm(PREFS), 0.4, 0.0001, "the view save erased the volume")
	assert_false(Prefs.load_hud(PREFS), "the view save erased the HUD choice")
	assert_true(Prefs.save_bgm(0.9, PREFS), "re-saving the volume failed")
	assert_eq(Prefs.load_mode(PREFS), "goals", "the volume save erased the view")


func test_the_bar_door_cycles_all_three_views() -> void:
	game.view.set_mode("highlights")
	assert_eq(_band_label("mode"), "HIGHLIGHTS", "the door opened on the wrong view")
	_tap_door("mode")
	assert_eq(game.mode, "goals", "the mode door skipped Goals only")
	assert_eq(_band_label("mode"), "GOALS ONLY", "the door does not name Goals only")
	assert_true(game.fast_mode, "Goals only did not fast-forward on open")
	_tap_door("mode")
	assert_eq(game.mode, "full", "Goals only did not lead to the full match")
	assert_eq(_band_label("mode"), "FULL MATCH", "the door does not name the full match")
	assert_false(game.fast_mode, "the full match kept the fast-forward")
	_tap_door("mode")
	assert_eq(game.mode, "highlights", "the full match did not lead back to Highlights")
	assert_true(game.fast_mode, "Highlights did not resume fast-forwarding")

func test_h_cycles_the_same_three_views() -> void:
	game.view.set_mode("highlights")
	_key(KEY_H)
	assert_eq(game.mode, "goals", "H did not reach Goals only")
	_key(KEY_H)
	assert_eq(game.mode, "full", "H did not reach the full match")
	_key(KEY_H)
	assert_eq(game.mode, "highlights", "H did not come back to Highlights")

func test_a_toggle_remembers_the_view_and_a_relaunch_restores_it() -> void:
	game.view.set_mode("highlights")
	_key(KEY_H)
	assert_eq(Prefs.load_mode(PREFS), "goals", "the toggle did not save Goals only")

	game.view.set_mode("highlights")
	game.menus.restore_mode()
	assert_eq(game.mode, "goals", "a relaunch did not restore Goals only")
	assert_true(game.fast_mode, "a restored Goals only did not fast-forward")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
	game.menus.restore_mode()
	assert_eq(game.mode, "highlights", "a cleared cache did not open in Highlights")

func test_goals_only_fast_forwards_and_the_full_match_does_not() -> void:
	game.view.set_mode("goals")
	assert_true(game.fast_mode, "Goals only is not fast-forwarding")
	assert_eq(game.view.ticks_this_frame(1.0 / 30.0), 48, "a Goals only frame ran the wrong number of ticks")
	game.view.set_mode("full")
	assert_false(game.fast_mode, "the full match is fast-forwarding")
	game.speed = 2.0
	assert_eq(game.view.ticks_this_frame(1.0 / 30.0), 4, "the full match ignored the chosen speed")
	game.speed = 1.0

func test_skip_ends_a_live_replay_in_goals_only() -> void:
	game.view.set_mode("goals")
	game.in_highlight = true
	game.fast_mode = false
	game.highlight_until = game.engine.clock + 12.0
	_key(KEY_S)
	assert_false(game.in_highlight, "Skip did not end the goal replay")
	assert_true(game.fast_mode, "Skip left Goals only standing still")


func test_skip_runs_the_match_on_to_the_next_whistle() -> void:
	engine_dirty = true
	game.view.set_mode("highlights")
	game.paused = false
	game.engine.added = [1.0, 1.0]
	game.engine.clock = 2699.4
	_key(KEY_S)
	assert_true(game.skip_armed, "a skip press did not arm the skip")
	assert_gt(float(game.engine.clock), 2699.4, "a skip press moved the match nowhere")
	var calls := 0
	while str(game.engine.phase) != "half_time" and calls < 200:
		game.playback.advance_skip()
		calls += 1
	assert_eq(str(game.engine.phase), "half_time", "the skip did not reach the half-time whistle")
	assert_false(game.skip_armed, "the skip stayed armed past the whistle")
	assert_gte(float(game.engine.clock), 2700.0, "the skip stopped short of half time")


func test_a_skip_spends_one_frame_budget_at_a_time() -> void:
	engine_dirty = true
	game.view.set_mode("highlights")
	game.paused = false
	game.engine.clock = 60.0
	_key(KEY_S)
	var before := float(game.engine.clock)
	game._process(1.0 / 60.0)
	var spent := float(game.engine.clock) - before
	assert_gt(spent, 0.0, "a skip frame moved nothing")
	assert_lt(spent, 60.0, "one skip frame ran a whole match minute")
	assert_true(game.skip_armed, "a skip frame ran out of match to skip")


func test_a_second_skip_press_stops_it() -> void:
	engine_dirty = true
	game.view.set_mode("highlights")
	game.paused = false
	game.engine.clock = 120.0
	_key(KEY_S)
	assert_true(game.skip_armed, "a skip press did not arm the skip")
	_key(KEY_S)
	assert_false(game.skip_armed, "a second press did not stop the skip")


func test_pause_stops_a_running_skip() -> void:
	engine_dirty = true
	game.view.set_mode("highlights")
	game.paused = false
	game.engine.clock = 200.0
	_key(KEY_S)
	assert_true(game.skip_armed, "a skip press did not arm the skip")
	_key(KEY_SPACE)
	assert_true(game.paused, "space did not pause the match")
	game._process(1.0 / 60.0)
	assert_false(game.skip_armed, "a paused match kept skipping")


func test_a_finished_match_cannot_skip_and_a_break_holds_the_skip_off() -> void:
	engine_dirty = true
	game.engine.phase = "full_time"
	game.paused = false
	_key(KEY_S)
	assert_false(game.skip_armed, "a finished match armed a skip")
	game.engine.phase = "half_time"
	_key(KEY_S)
	assert_false(game.skip_armed, "a half-time break armed a skip")
	game.engine.phase = "play"


func test_the_state_line_and_the_door_name_a_running_skip() -> void:
	engine_dirty = true
	var band: HudRosterBand = game.hud.roster_band
	game.view.set_mode("highlights")
	game.paused = false
	game.engine.clock = 300.0
	assert_eq(band.state_label(game, "SIM", "play"), "HIGHLIGHTS  ·  SIMMING 24x",
		"the idle Highlights line moved")
	_key(KEY_S)
	assert_eq(band.state_label(game, "SIM", "play"), "SKIPPING  ·  TO HALF TIME",
		"the state line did not name the skip")
	assert_eq(_band_label("skip"), "STOP", "the door did not offer to stop the skip")
	_key(KEY_S)
	assert_eq(_band_label("skip"), "SKIP", "the door did not go back to SKIP")


func test_a_skip_in_the_second_half_names_full_time() -> void:
	engine_dirty = true
	game.view.set_mode("full")
	game.paused = false
	game.engine.half = 2
	game.engine.clock = 3000.0
	_key(KEY_S)
	assert_eq(HudRosterBand.skip_label(game.engine), "SKIPPING  ·  TO FULL TIME",
		"the second half's skip named the wrong whistle")
	_key(KEY_S)

func test_goals_only_replays_only_scored_goals() -> void:
	game.view.set_mode("goals")


	var engine = MatchEngine.new(4242, "MUN", "MCI")
	game.engine = engine
	engine_dirty = true
	game.highlights.restart()
	for i in range(90):
		engine.tick()
		game.highlights.sample()
	var director: HighlightDirector = game.highlights
	var clock := float(engine.clock)
	director.on_event({"type": "shot", "clock": clock, "player_id": 7})
	assert_false(director.waiting(), "a shot queued a replay in Goals only")
	director.on_event({"type": "corner", "clock": clock, "player_id": -1})
	assert_false(director.waiting(), "a corner queued a replay in Goals only")
	director.on_event({"type": "card", "clock": clock, "player_id": 8})
	assert_false(director.waiting(), "a card queued a replay in Goals only")
	director.on_event({"type": "penalty_taken", "clock": clock, "player_id": 9})
	assert_false(director.waiting(), "a penalty that missed queued a replay in Goals only")
	director.on_event({"type": "goal", "clock": clock, "player_id": 9, "team": 0, "text": "GOAL!"})
	assert_true(director.waiting(), "a scored goal did not queue a replay in Goals only")
	for i in range(180):
		engine.tick()
		game.highlights.sample()
		if game.replay != null:
			break
	assert_true(game.in_highlight, "a scored goal did not open a replay in Goals only")
	assert_not_null(game.replay, "Goals only opened no clip for the goal")
	game.replay.finish(true)
	game.replay = null
	game.view.set_mode("highlights")
	director.on_event({"type": "shot", "clock": float(engine.clock) + 0.5, "player_id": 10})
	assert_true(director.waiting(), "Highlights stopped queuing shots")
	for i in range(180):
		engine.tick()
		game.highlights.sample()
		if game.replay != null:
			break
	assert_true(game.in_highlight, "Highlights stopped replaying shots")
	game.replay.finish(true)
	game.replay = null

func test_the_state_line_names_the_view() -> void:
	var band: HudRosterBand = game.hud.roster_band
	var bar: HudControlsBand = game.hud.controls_band
	game.view.set_mode("goals")
	game.paused = false
	game.fast_mode = true
	assert_eq(band.state_label(game, bar.speed_label(game)), "GOALS ONLY  ·  SIMMING 24x", "the simming line does not name Goals only")
	game.fast_mode = false
	assert_eq(band.state_label(game, bar.speed_label(game)), "GOALS ONLY  ·  LIVE", "the live line does not name Goals only")
	game.view.set_mode("full")
	game.speed = 2.0
	assert_eq(bar.speed_label(game), "2x", "the speed door lost its multiplier")
	assert_eq(band.state_label(game, bar.speed_label(game)), "FULL MATCH  ·  2x", "the full-match line lost its speed")
	game.paused = true
	assert_eq(band.state_label(game, bar.speed_label(game)), "PAUSED", "the paused line lost its word")


func test_the_speed_door_never_reads_simx() -> void:
	var bar: HudControlsBand = game.hud.controls_band
	var band: HudRosterBand = game.hud.roster_band
	var paint := HudPaint.new(game.hud.chrome, game.hud.design_vp())
	game.paused = false
	game.view.set_mode("highlights")
	game.fast_mode = true
	var label := _speed_door(bar, paint)
	assert_eq(label, "SIM", "a simming replay view shows a multiplier on its speed door")
	assert_false(label.ends_with("x"), "the door glued the multiplier's x onto the sim word")
	assert_true(band.state_label(game, label).contains("SIMMING"), "the door and the state line name different states")

	game.view.set_mode("full")
	game.speed = 4.0
	assert_eq(_speed_door(bar, paint), "4x", "the full match lost its speed on the door")
	assert_true(band.state_label(game, bar.speed_label(game)).ends_with("4x"), "the state line lost the same rate")

func _speed_door(bar: HudControlsBand, paint: HudPaint) -> String:
	for spec in bar.control_specs(paint, game, false):
		if str(spec[0]) == "speed":
			return str(spec[1])
	return ""

func test_the_simulating_chip_waits_for_a_goal_in_goals_only() -> void:
	assert_true(HudTopBand.sim_chip_label("goals").contains("NEXT GOAL"), "Goals only still waits on the next chance")
	assert_true(HudTopBand.sim_chip_label("highlights").contains("NEXT CHANCE"), "Highlights stopped waiting on chances")

func test_the_state_line_and_chip_leave_with_the_whistle() -> void:


	var band: HudRosterBand = game.hud.roster_band
	game.view.set_mode("highlights")
	game.paused = false
	game.fast_mode = true
	game.match_time = 30.0
	assert_true(HudTopBand.chip_shown(game.mode, game.fast_mode, game.paused, game.match_time, "play"),
		"the chip left a simming Highlights match")
	assert_eq(band.state_label(game, "SIM", "play"), "HIGHLIGHTS  ·  SIMMING 24x",
		"a live Highlights match lost its simming line")
	assert_false(HudTopBand.chip_shown(game.mode, game.fast_mode, game.paused, game.match_time, "full_time"),
		"the chip stayed over a finished match")
	assert_eq(band.state_label(game, "SIM", "full_time"), "FULL TIME  ·  MATCH OVER",
		"a finished match still claimed to be live")
	assert_eq(band.state_label(game, "2", "full_time"), "FULL TIME  ·  MATCH OVER",
		"the full-match speed outlived the whistle")


func test_settings_shows_and_sets_the_same_view() -> void:
	game.menus.open_settings()
	var shell = game.menus.shell
	assert_eq(shell.match_mode, "highlights", "the sheet did not read the saved view")
	var segs: Array = SettingsScreen.seg_rects(shell.design_vp())
	shell.click((segs[1] as Rect2).get_center())
	assert_eq(shell.match_mode, "goals", "the Goals only segment did not take")
	assert_eq(Prefs.load_mode(PREFS), "goals", "the segment did not save the view")
	assert_eq(game.mode, "goals", "the match did not follow the settings choice")
	shell.click((segs[2] as Rect2).get_center())
	assert_eq(game.mode, "full", "the full-match segment did not reach the match")
	assert_false(game.fast_mode, "the full match kept the fast-forward")
	shell.click((segs[0] as Rect2).get_center())
	assert_eq(game.mode, "highlights", "the Highlights segment did not take")
	assert_eq(Prefs.load_mode(PREFS), "highlights", "the last segment did not save")

func test_settings_keys_reach_the_three_views() -> void:
	game.menus.open_settings()
	var shell = game.menus.shell
	assert_true(shell.key(KEY_2), "2 did not reach the view row")
	assert_eq(shell.match_mode, "goals", "2 did not choose Goals only")
	assert_true(shell.key(KEY_3), "3 did not reach the view row")
	assert_eq(shell.match_mode, "full", "3 did not choose the full match")
	assert_true(shell.key(KEY_1), "1 did not reach the view row")
	assert_eq(shell.match_mode, "highlights", "1 did not choose Highlights")

func test_the_segments_are_finger_sized_and_on_the_card() -> void:
	for vp in _vps():
		var card: Rect2 = SettingsScreen.card_rect(vp)
		var segs: Array = SettingsScreen.seg_rects(vp)
		assert_eq(segs.size(), 3, "the view row is not three segments at %s" % vp)
		for i in range(segs.size()):
			var r: Rect2 = segs[i]
			assert_gte(r.size.y, 44.0, "a segment is under the 44-unit tap floor at %s" % vp)
			assert_true(card.encloses(r), "a segment left the card at %s" % vp)
			assert_false(r.intersects(SettingsScreen.track_rect(vp)), "a segment covers the volume track at %s" % vp)
			assert_false(r.intersects(SettingsScreen.hud_toggle_rect(vp)), "a segment covers the HUD switch at %s" % vp)
			assert_false(r.intersects(SettingsScreen.minus_rect(vp)), "a segment covers a volume step at %s" % vp)
			assert_false(r.intersects(SettingsScreen.back_rect(vp)), "a segment covers BACK at %s" % vp)
			assert_eq(game.menus.shell.settings.button_at(r.get_center(), vp), "mode:%s" % Prefs.MODES[i],
				"segment %d did not answer a press at %s" % [i, vp])
