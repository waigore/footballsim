extends SceneTree

## Evidence capture for issue #277: with a match waiting behind the in-match
## menu, the gold door is RESUME MATCH and the footer advertises `ENTER  RESUME
## MATCH`; a cold-start menu keeps START SIM gold and `ENTER  START SIM`.
##
## Shoots both poses on a desktop design space and the phone design space, then
## presses the advertised key for real and prints where it landed, so the log
## carries the proof beside the pixels.
##
##   godot --path . --resolution 1600x900 --script res://tools/issue277_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	# Cold start: no match behind the menu.
	scene.match_started = false
	scene.menus.open_menu()
	await _shot("issue277_desktop_cold")
	_dump("desktop cold")
	# A paused match behind the menu — the pose the playtest caught.
	scene.match_started = true
	scene.paused = true
	scene.menus.open_menu()
	await _shot("issue277_desktop_waiting")
	_dump("desktop waiting")
	# The advertised key, pressed for real.
	var resumed: bool = scene.menus.shell.key(KEY_ENTER)
	print("ENTER resumed=%s select_open=%s paused=%s shell_active=%s hud=%s"
		% [str(resumed), str(scene.select_open), str(scene.paused),
		str(scene.menus.active()), str(scene.hud_layer.visible)])
	await _shot("issue277_desktop_after_enter")

	# The phone design space (a 913x411 handset at the overlay scale).
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	scene.menus.shell.touch = true
	scene.paused = true
	scene.menus.open_menu()
	await _shot("issue277_phone_waiting")
	_dump("phone waiting")
	print("EXIT done")
	quit()

func _dump(label: String) -> void:
	var shell = scene.menus.shell
	var vp: Vector2 = shell.design_vp()
	var primary := MenuScreen.primary_id(shell.has_match)
	print("POSE %s vp=%s has_match=%s primary=%s footer=%s"
		% [label, str(vp), str(shell.has_match), primary,
		MenuScreen.footer_hint(shell.has_match, shell.touch)])
	for b in MenuScreen.door_rects(vp, shell.has_match):
		var r: Rect2 = b["rect"]
		var id := str(b["id"])
		print("  door %-12s rect=%s hint=%s gold=%s"
			% [id, str(r), str(MenuScreen.door_hints(shell.has_match).get(id, "")),
			str(id == primary)])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
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
