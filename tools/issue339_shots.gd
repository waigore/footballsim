extends SceneTree

## Evidence capture for #339: with the match HUD hidden the on-pitch action stays
## painted. Shirt numbers and near-ball surnames ride the tokens whether the
## chrome bands are up or gone; only the chrome leaves.
##
## Boots the real game scene and shoots:
##
##   * desktop 1600x900 with the chrome up (the `match-hud` catalogue screen),
##   * desktop 1600x900 with the chrome hidden (the new `match-hud-hidden`
##     catalogue screen, and the baseline the UX VLM gate grades),
##   * the same hidden pose on a phone's design space.
##
## Every shot prints how many shirt numbers the overlay asked to paint, so the
## log proves the rule as well as the PNG shows it.
##
##   xvfb-run -a godot --path . --script res://tools/issue339_shots.gd
##
## Writes a PNG per pose into `res://shots/` (git-ignored).

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "MCI")
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.kick_off.emit()
		await _frames(2)
	# A live frame of play: the clock running, a score on the board, the ball
	# with a player so surnames are near it.
	scene.paused = false
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.paused = true
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue339_desktop_shown")
	_print_pose("desktop shown", false)
	# The pose the issue is about: chrome fully gone.
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("issue339_desktop_hidden")
	_print_pose("desktop hidden", true)
	# Half way through the glide: the bands are moving, the labels are not
	# fading. The overlay's own easing is paused for the pose, or the frames the
	# capture waits on would finish the slide before the shot.
	scene.hud.set_process(false)
	scene.hud.set_hud_visible(true, true)
	scene.hud.set_hud_visible(false)
	scene.hud.slide = 0.5
	scene.hud.queue_redraw()
	await _shot("issue339_desktop_midslide")
	_print_pose("desktop midslide", false)
	scene.hud.set_hud_visible(false, true)
	scene.hud.set_process(true)
	# Phone design space: the same hidden pose at a handset's overlay scale. A
	# phone's wide framing keeps the numbers for a zoomed-in view (the rule is
	# unchanged, #339), so the pose is the follow camera a handset opens in.
	scene.dev.ui_scale = 2.2
	scene._sync_overlay_scale()
	scene.camera_follow = true
	scene._apply_camera(true)
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("issue339_phone_hidden")
	_print_pose("phone hidden", true)
	# Leave the developer's own prefs as they were.
	scene.hud.set_hud_visible(true)
	print("EXIT touch=", scene.touch, " scale=", scene.hud_scale)
	quit()

## Count the shirt numbers the overlay's roster band actually paints this frame,
## read through the band's own gates (the phone size rule and the viewport cull),
## so the pose's log names the rule as well as the PNG shows it.
func _numbers_painted() -> int:
	var def := HudPaint.new(scene.hud.chrome, scene.hud.design_vp())
	var zoom: float = scene.get_viewport().get_canvas_transform().get_scale().x
	var s: float = maxf(scene.hud.ui_scale, 0.001)
	var r: float = 0.86 * zoom * scene.token_scale / s
	if def.compact() and r < 6.0:
		return 0
	var vp: Vector2 = scene.hud.design_vp()
	var n := 0
	for pl in scene.engine.players:
		if pl.sent_off:
			continue
		var sp: Vector2 = scene.hud.roster_band.w2s(def, scene.hud, pl.pos - Vector2(0, pl.z * 0.55))
		if sp.x < -40.0 or sp.x > vp.x + 40.0 or sp.y < -40.0 or sp.y > vp.y + 40.0:
			continue
		n += 1
	return n

func _print_pose(label: String, hidden: bool) -> void:
	var vp: Vector2 = scene.hud.design_vp()
	print("%s: design vp=%s compact=%s hidden=%s shown=%s slide=%.2f names=%s numbers=%d" % [
		label, vp, HudLayout.is_compact(vp), hidden, scene.hud.hud_visible, scene.hud.slide,
		scene.names_visible, _numbers_painted()])

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
	print("SHOT shots/%s.png %s" % [name, img.get_size()])
