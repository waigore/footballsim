extends SceneTree

## Verify the merged finish control (#249, PR #254) against the issue's own
## acceptance on a handset: the chips must be tappable and must not sit under
## the KICK OFF doors. Prints the geometry so it can be read without a picture.

func _initialize() -> void:
	var scene: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	for pose in [[0.0, "desktop_1600x900"], [HudLayout.scale_for(411.0), "phone_913x411"],
			[HudLayout.scale_for(360.0), "phone_640x360"]]:
		await _pose(scene, float(pose[0]), str(pose[1]))
	quit()

func _pose(scene, scale: float, name: String) -> void:
	scene.dev.ui_scale = scale
	scene._sync_overlay_scale()
	scene.open_select(true)
	scene.selector.setup("MUN", "MCI")
	scene.selector.queue_redraw()
	await _frames(5)
	var sel = scene.selector
	var vp: Vector2 = sel.design_vp()
	var card_h: float = minf(vp.y * 0.32, 250.0)
	var card_y: float = vp.y * 0.42 - card_h * 0.5
	var chips: Array = LeagueChrome.winner_rects(vp, card_y + card_h)
	var doors: Array = []
	for b in sel.buttons:
		if str(b["id"]) == "confirm" or str(b["id"]) == "random" or str(b["id"]).begins_with("win:"):
			doors.append([str(b["id"]), b["rect"]])
	print("=== ", name, " vp=", vp, " touch=", sel.touch, " mode=", sel.winner_mode)
	for chip in chips:
		print("  chip ", chip["id"], " ", chip["rect"], " h=", (chip["rect"] as Rect2).size.y)
	for d in doors:
		print("  door ", d[0], " ", d[1])
	# Does any KICK OFF door overlap a chip?
	for chip in chips:
		for d in doors:
			if str(d[0]) == "win:draw" or str(d[0]) == "win:extra":
				continue
			if (chip["rect"] as Rect2).intersects(d[1]):
				print("  !! OVERLAP ", chip["id"], " x ", d[0])
	await _shot(scene, "check249_" + name)
	scene.fixture.close()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(scene, name: String) -> void:
	await _frames(3)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		return
	var img: Image = tex.get_image()
	if img == null:
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
