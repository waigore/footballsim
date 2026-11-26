extends SceneTree

## Evidence capture for issue #276: a finished match used to keep the live
## `HIGHLIGHTS · LIVE` state line and live PAUSE, speed and SKIP doors. After the
## whistle the line now reads `FULL TIME · MATCH OVER`, those three doors keep
## their boxes but answer nothing, and the simulating chip is gone.
##
## Boots the real game scene and shoots:
##
##   * desktop full time with the chrome up,
##   * phone full time with the chrome up.
##
## It also prints every door the overlaid bar answered with at each pose, and
## what a press on the dead cells reads as. Run it on a display; a headless run
## has no frame to read back.
##
##   godot --path . --script res://tools/issue276_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "MCI")
	# The briefing is the last screen before a watched match (#157).
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.kick_off.emit()
	await _frames(2)
	scene.paused = false
	scene.hud.set_hud_visible(true, true)
	# A played-out match: the score, the goal sheet and the engine's own phase.
	scene.engine.clock = 90.0 * 60.0
	scene.engine.half = 2
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.engine.goal_sheet = [
		{"team": 0, "minute": 22, "scorer": "P. Foden", "own_goal": false},
		{"team": 1, "minute": 57, "scorer": "B. Šeško", "own_goal": false},
		{"team": 0, "minute": 78, "scorer": "E. Haaland", "own_goal": false},
	]
	scene.engine.phase = "full_time"
	# The match's own log, so the ticker shows the whistle line it would hold in a
	# real match rather than the empty-screen placeholder.
	scene.engine.events = [
		{"id": 1, "type": "kickoff", "text": "Kick-off! Manchester City to get us going.", "minute": 0},
		{"id": 2, "type": "goal", "text": "GOAL! P. Foden finds the far corner.", "minute": 22},
		{"id": 3, "type": "goal", "text": "GOAL! B. Šeško levels it.", "minute": 57},
		{"id": 4, "type": "goal", "text": "GOAL! E. Haaland heads it in.", "minute": 78},
		{"id": 5, "type": "full_time", "text": "Full time: MUN 2-1 MCI. MUN take it.", "minute": 90},
	]
	scene.fast_mode = false
	scene.hud.ticker.hold = 0.0
	scene.hud.queue_redraw()
	await _shot("issue276_desktop_fulltime")
	_print_pose("desktop full time")
	# The state line and the chip in the same phase, read back as copy.
	print("STATE ", scene.hud.roster_band.state_label(scene, scene.hud.controls_band.speed_label(scene), "full_time"))
	print("CHIP shown=", HudTopBand.chip_shown(scene.mode, scene.fast_mode, scene.paused, scene.match_time, "play"),
		" over=", HudTopBand.chip_shown(scene.mode, scene.fast_mode, scene.paused, scene.match_time, "full_time"))
	print("RESTART door=", scene.hud.controls_band.control_specs(
		HudPaint.new(scene.hud.chrome, scene.hud.design_vp()), scene, scene.hud.touch, "full_time")[6][1])
	# Phone design space: the compact bar carries the teams door too.
	scene.dev.ui_scale = 2.2
	scene._sync_overlay_scale()
	scene.hud.queue_redraw()
	await _shot("issue276_phone_fulltime")
	_print_pose("phone full time")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	# In play, the pose the screen catalogue grades the HUD on: the play doors are
	# live, the state line names the view, and the replay chip is up.
	scene.new_match(1000)
	scene.view.set_mode("highlights")
	scene.paused = false
	scene.fast_mode = true
	scene.match_time = 40.0
	scene.engine.clock = 63.0 * 60.0
	scene.engine.half = 2
	scene.engine.score[0] = 1
	scene.engine.score[1] = 1
	scene.engine.events = [
		{"id": 1, "type": "kickoff", "text": "Kick-off! Manchester City to get us going.", "minute": 0},
		{"id": 2, "type": "goal", "text": "GOAL! P. Foden finds the far corner.", "minute": 22},
		{"id": 3, "type": "goal", "text": "GOAL! B. Šeško levels it.", "minute": 57},
	]
	scene.hud.ticker.hold = 0.0
	scene.hud.queue_redraw()
	await _shot("issue276_desktop_in_play")
	_print_pose("desktop in play")
	quit()

## Every door the overlay answered with at this pose, in draw order, plus the
## strip's own cells for the doors that no longer answer.
func _print_pose(label: String) -> void:
	var vp: Vector2 = scene.hud.design_vp()
	var bar: Rect2 = HudLayout.controls_rect(vp, scene.hud.touch)
	var bw: float = HudLayout.control_width(vp, scene.hud.touch)
	print("%s: vp=%s bar=%s" % [label, vp, bar])
	for b in scene.hud.buttons:
		print("  door %s %s" % [b["id"], b["rect"]])
	for i in [0, 1, 3]:
		var cell := Rect2(bar.position.x + float(i) * (bw + HudLayout.CONTROL_GAP), bar.position.y, bw, HudLayout.CONTROL_H)
		print("  dead cell %d %s press=%s" % [i, cell, scene.hud.button_at(cell.get_center())])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(4)
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
	print("SHOT ", name, " ", img.get_size(), " ", hash(img.get_data()))
