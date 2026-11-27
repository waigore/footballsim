extends SceneTree

## Evidence capture for #370: a phone's encyclopedia league page opens on the
## table instead of one club.
##
## Shoots the league page at the handset design space (411 dp, the phone's own
## 1 design unit = 1 dp), at the narrower 360 dp pose, and at the desktop sheet
## (1600 × 900), so the dense reading is checked as well as the phone one.
## Writes a PNG per pose into `res://shots/`.
##
##   godot --path . --script res://tools/wiki_phone_table_shots.gd

var scene = null

func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	await _pose(Vector2(914.0, 411.0), "issue370_league_411")
	await _pose(Vector2(640.0, 360.0), "issue370_league_360")
	await _pose(Vector2(1600.0, 900.0), "issue370_league_1600")
	print("EXIT done")
	quit()

func _pose(vp: Vector2, name: String) -> void:
	root.size = Vector2i(roundi(vp.x), roundi(vp.y))
	await _frames(3)
	scene.dev.ui_scale = 0.0
	scene.hud_scale = 1.0
	scene.chrome_scale = 1.0
	scene.touch = vp.y < 620.0
	scene.menus.sync(Transform2D.IDENTITY, 1.0, scene.touch)
	if scene.wiki_host == null:
		return
	scene.wiki_host.screen.touch = scene.touch
	scene.wiki_host.sync_scale()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _frames(4)
	var screen = scene.wiki_host.screen
	var shown := 0
	for row in screen.body.rows():
		var r: Rect2 = row["rect"]
		if str(row["k"]) == "trow" and r.position.y >= 0.0 and r.end.y <= screen.body.size.y:
			shown += 1
	print("POSE %s design=%s header=%.1f body=%.1f club_rows=%d strip=%d" % [
		name, str(screen.design_vp()), screen.body.position.y, screen.body.size.y, shown,
		screen.strip_rects.size()])
	await _capture(name)
	scene.wiki_host.close()
	await _frames(2)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _capture(name: String) -> void:
	await _frames(3)
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
