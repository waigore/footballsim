extends SceneTree

## Evidence capture for issue #164 (sub-issues #165/#166): the third match view.
##
## Boots the real game scene and shoots:
##
##   * Highlights simming: the "next chance" chip, the status line, the bar door,
##   * Goals only simming: the "next goal" chip, `GOALS ONLY · SIMMING 24x`,
##   * Goals only live: a goal replay open, the status line reading `· LIVE`,
##   * Full Match: the speed on the status line and the door reading FULL MATCH,
##   * the Settings sheet with each of the three segments chosen,
##   * the phone design space: the match bar door and the Settings row.
##
## Writes a PNG per pose into `res://shots/` and prints the geometry it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/match_mode_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("ENG-MUN1", "ENG-MCI1")
	# #157: the briefing comes before the sim, so kick it off.
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")
		await _frames(2)
	# The poses are stills: leave the loop un-paused so the status line reads the
	# view, and stop the scene's tick so nothing moves between posing and capture.
	scene.paused = false
	scene.set_process(false)
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.match_time = 14.0
	scene.hud.set_hud_visible(true, true)
	# Highlights simming: the chip waits on the next chance.
	scene.view.set_mode("highlights")
	scene.fast_mode = true
	scene.hud.queue_redraw()
	await _shot("issue164_highlights_simming")
	_print_state("highlights simming")
	# Goals only simming: the chip waits on the next goal.
	scene.view.set_mode("goals")
	scene.fast_mode = true
	scene.hud.queue_redraw()
	await _shot("issue164_goals_simming")
	_print_state("goals only simming")
	# Goals only live: a goal replay is open, so the status line reads LIVE.
	scene.in_highlight = true
	scene.fast_mode = false
	scene.highlight_until = scene.engine.clock + 12.0
	scene.replay_banner = 2.2
	scene.hud.queue_redraw()
	await _shot("issue164_goals_live")
	_print_state("goals only live")
	# Full match: the player's speed runs the match.
	scene.view.set_mode("full")
	scene.speed = 2.0
	scene.replay_banner = 0.0
	scene.hud.queue_redraw()
	await _shot("issue164_full_match")
	_print_state("full match 2x")
	# The Settings sheet: each segment chosen in turn.
	scene.hud.set_hud_visible(true)
	scene.menus.open_settings()
	var shell = scene.menus.shell
	var segs: Array = SettingsLayout.seg_rects(shell.design_vp())
	for i in range(segs.size()):
		shell.click((segs[i] as Rect2).get_center())
		await _shot("issue164_settings_%s" % Prefs.MODES[i])
		_print_settings(str(Prefs.MODES[i]))
	shell.click((segs[1] as Rect2).get_center())
	scene.menus.close()
	# Phone design space: the same two surfaces at the handset scale.
	scene.dev.ui_scale = 2.2
	scene._sync_overlay_scale()
	scene.hud_layer.visible = true
	scene.view.set_mode("goals")
	scene.fast_mode = true
	scene.hud.queue_redraw()
	await _shot("issue164_phone_goals_simming")
	_print_state("phone goals simming")
	scene.menus.open_settings()
	await _shot("issue164_phone_settings")
	_print_settings("phone goals")
	scene.menus.close()
	# A portrait design space: the card is narrower than the inline threshold, so
	# the MATCH VIEW title stacks above its segments instead of sharing the line.
	DisplayServer.window_set_size(Vector2i(1200, 1400))
	await _frames(4)
	scene.dev.ui_scale = 3.2
	scene._sync_overlay_scale()
	scene.menus.open_settings()
	await _shot("issue164_portrait_settings")
	_print_settings("portrait goals")
	scene.menus.close()
	# Leave the developer's own prefs as they were: the captures must not decide
	# how the next launch opens.
	Prefs.save_mode(Prefs.DEFAULT_MODE)
	scene.view.set_mode(Prefs.DEFAULT_MODE)
	print("EXIT mode=", scene.mode, " touch=", scene.touch, " scale=", scene.hud_scale)
	quit()

func _print_state(label: String) -> void:
	var p := HudPaint.new(scene.hud.chrome, scene.hud.design_vp())
	var specs: Array = scene.hud.controls_band.control_specs(p, scene, scene.touch)
	var door := ""
	for spec in specs:
		if str(spec[0]) == "mode":
			door = str(spec[1])
	var label_line: String = scene.hud.roster_band.state_label(scene, scene.hud.controls_band.speed_label(scene))
	var chip := "" if scene.mode == "full" else HudTopBand.sim_chip_label(scene.mode)
	print("%s: mode=%s door=%s chip=%s status=%s fast=%s" % [label, scene.mode, door,
		chip, label_line, scene.fast_mode])

func _print_settings(label: String) -> void:
	var vp: Vector2 = scene.menus.shell.design_vp()
	print("%s: settings vp=%s card=%s mode=%s segs=%s" % [label, vp, SettingsLayout.card_rect(vp),
		scene.menus.shell.match_mode, SettingsLayout.seg_rects(vp)])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
	# Force the draw stage before reading back: a queued redraw that has not
	# reached it saves the previous pose, and an occluded window may not draw.
	RenderingServer.force_draw(false)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT ", name, " ", img.get_size())
