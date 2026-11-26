extends SceneTree

## Evidence capture for issue #202: with the match HUD hidden the full-time card
## used to say `TAP RESTART TO PLAY AGAIN` while RESTART sat on the bar the
## setting had taken away. The card now names, and answers, its own press, and
## the Settings row says what `ON` means.
##
## Boots the real game scene and shoots:
##
##   * desktop full time with the chrome up (the bar still carries RESTART),
##   * desktop full time with the chrome hidden (a key hint, as before),
##   * phone full time with the chrome up (card names the bar's RESTART),
##   * phone full time with the chrome hidden (card names its own press),
##   * phone paused with the chrome hidden (the banner resumes on tap),
##   * the phone Settings sheet's MATCH HUD row, ON and OFF.
##
## Writes a PNG per pose into `res://shots/` and prints every door it read back.
## Run it on a display; a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/issue202_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "MCI")
	# The briefing is the last screen before a watched match (#157): start it the
	# way a player does, so every pose below is the broadcast.
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.kick_off.emit()
	await _frames(2)
	# The card poses are the broadcast with nothing over it: only the PAUSED
	# pose below is paused, so its banner is the one the evidence shows.
	scene.paused = false
	scene.engine.clock = 90.0 * 60.0
	scene.engine.score[0] = 1
	scene.engine.score[1] = 0
	scene.engine.goal_sheet = [
		{"team": 0, "minute": 57, "scorer": "P. Foden", "own_goal": false},
	]
	scene.engine.phase = "full_time"
	# Desktop: the bar is up and carries RESTART.
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue202_desktop_shown")
	_print_pose("desktop shown")
	# Desktop: hidden chrome, the card keeps the key hint it always printed.
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("issue202_desktop_hidden")
	_print_pose("desktop hidden")
	# Phone design space: the pose a handset presents, touch copy.
	scene.dev.ui_scale = 2.2
	scene._sync_overlay_scale()
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue202_phone_shown")
	_print_pose("phone shown")
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("issue202_phone_hidden")
	_print_pose("phone hidden")
	# The card is the door: a tap on it plays again (the restart rebuilds the
	# engine, so read the pose before pressing).
	var before = scene.engine
	var card: Rect2 = _card()
	scene._click(card.get_center() * scene.hud_scale)
	print("TAP card=", card, " restarts=", scene.engine != before, " phase=", scene.engine.phase)
	scene.paused = true
	# Paused with the chrome hidden: the banner is the RESUME door.
	scene.engine.phase = "kickoff"
	scene.paused = true
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("issue202_phone_hidden_paused")
	_print_pose("phone hidden paused")
	# The Settings row: ON is chrome shown, and the caption now says so. The
	# caption only fits a roomy row, so this pose is desktop metrics.
	scene.paused = false
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	scene.hud.set_hud_visible(true)
	scene.menus.open_settings()
	await _shot("issue202_settings_on")
	print("settings vp=", scene.menus.shell.design_vp(), " caption=", SettingsScreen.HUD_ROW_HINT)
	scene.menus.shell.click(SettingsScreen.hud_toggle_rect(scene.menus.shell.design_vp()).get_center())
	await _shot("issue202_settings_off")
	scene.menus.shell.click(SettingsScreen.hud_toggle_rect(scene.menus.shell.design_vp()).get_center())
	scene.menus.close()
	scene.hud_layer.visible = true
	scene.hud.set_hud_visible(true)
	print("EXIT caption=", SettingsScreen.HUD_ROW_HINT, " touch=", scene.hud.touch)
	quit()

func _card() -> Rect2:
	var vp: Vector2 = scene.hud.design_vp()
	var eng = scene.engine
	return HudLayout.break_metrics(vp, eng.score[0], eng.score[1])["rect"]

## Every door the overlay answered with at this pose, in draw order.
func _print_pose(label: String) -> void:
	var vp: Vector2 = scene.hud.design_vp()
	print("%s: vp=%s card=%s hint_full_hidden=%s" % [label, vp, _card(),
		HudBannersBand.break_hint(str(scene.engine.phase), scene.hud.touch, true, bool(scene.result_hold))])
	for b in scene.hud.buttons:
		print("  door %s %s" % [b["id"], b["rect"]])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(4)
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
