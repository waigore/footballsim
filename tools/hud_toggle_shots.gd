extends SceneTree

## Evidence capture for issue #158: the match HUD hides and shows its chrome with
## a short slide, keeps the score and the match cards, leaves one discreet door,
## and remembers the choice; a phone opens in follow.
##
## Boots the real game scene and shoots:
##
##   * the desktop broadcast with the chrome up (the pill sits above the ticker),
##   * the same frame with the chrome hidden: scoreboard, pill and pitch only,
##   * half time with the chrome hidden: the whistle card still reads over it,
##   * the settings sheet with the MATCH HUD row ON and OFF,
##   * the phone design space with the chrome up and hidden.
##
## Writes a PNG per pose into `res://shots/` and prints the geometry it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/hud_toggle_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("ENG-MUN1", "ENG-MCI1")
	scene.paused = true
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue158_desktop_shown")
	_print_pill("desktop shown")
	scene.hud.set_hud_visible(false)
	scene.hud._process(1.0)
	scene.hud.queue_redraw()
	await _shot("issue158_desktop_hidden")
	_print_pill("desktop hidden")
	# Half way through the glide, so the capture shows the bands travelling
	# rather than a cut.
	scene.hud.slide = 0.5
	scene.hud.queue_redraw()
	await _shot("issue158_desktop_midslide")
	scene.hud.slide = 0.0
	scene.hud.queue_redraw()
	# Half time: the whistle card is a match card, so it stays over the pitch
	# while the bands are gone.
	scene.engine.goal_sheet = [
		{"team": 0, "minute": 23, "scorer": "B. Šeško", "own_goal": false},
		{"team": 1, "minute": 41, "scorer": "E. Haaland", "own_goal": false},
		{"team": 0, "minute": 77, "scorer": "B. Šeško", "own_goal": false},
	]
	scene.engine.phase = "half_time"
	scene.hud.queue_redraw()
	await _shot("issue158_desktop_hidden_halftime")
	# The settings sheet reads and writes the same pref as the pill and the key.
	scene.engine.phase = "kickoff"
	scene.hud.set_hud_visible(true)
	scene.menus.open_settings()
	await _shot("issue158_settings_on")
	scene.menus.shell.click(SettingsLayout.hud_toggle_rect(scene.menus.shell.design_vp()).get_center())
	await _shot("issue158_settings_off")
	scene.menus.shell.click(SettingsLayout.hud_toggle_rect(scene.menus.shell.design_vp()).get_center())
	scene.menus.close()
	scene.hud_layer.visible = true
	# Phone design space: the same two poses at the overlay scale a handset gets.
	scene.dev.ui_scale = 2.2
	scene._sync_overlay_scale()
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue158_phone_shown")
	_print_pill("phone shown")
	scene.hud.set_hud_visible(false)
	scene.hud._process(1.0)
	scene.hud.queue_redraw()
	await _shot("issue158_phone_hidden")
	_print_pill("phone hidden")
	# Leave the developer's own prefs as they were: the captures must not decide
	# how the next launch opens.
	scene.hud.set_hud_visible(true)
	print("EXIT follow=", scene.camera_follow, " touch=", scene.touch, " scale=", scene.hud_scale)
	quit()

func _print_pill(label: String) -> void:
	var vp: Vector2 = scene.hud.design_vp()
	var r: Rect2 = HudLayout.hud_toggle_rect(vp, scene.hud.touch)
	print("%s: design vp=%s pill=%s shown=%s slide=%.2f" % [label, vp, r, scene.hud.hud_visible, scene.hud.slide])

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
