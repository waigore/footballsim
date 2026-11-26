extends SceneTree

## Evidence capture for the UX VLM catalogue's match-hud baseline (#282): the
## whole desktop broadcast frame — top band, scoreboard, control bar and pitch —
## rather than the tight crop the old baseline carried. Also shoots the league
## hub, whose centre was too dark for the contrast rubric.
##
##   godot --path . --resolution 1600x900 --script res://tools/issue282_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "MCI")
	# The briefing holds for ten seconds of wall clock; take its kick door so the
	# frame is the broadcast itself.
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch._on_kick()
	await _frames(3)
	scene.paused = true
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("issue282_hud_desktop")
	print("EXIT phase=", scene.engine.phase, " hud=", scene.hud_layer.visible)
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(3)
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
