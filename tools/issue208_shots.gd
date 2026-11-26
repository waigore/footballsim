extends SceneTree

## Evidence capture for issue #208: a player page's empty states read as player
## copy, not as notes about the data pipeline. Shoots the same page three ways —
## the shipped file, a season with this player unused, and a phone viewport —
## and prints the blocks the sheet drew so the copy is in the log too.
##
## Run it on a display; a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/issue208_shots.gd

const PLAYER := "MUN-casemiro"

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	await _design(Vector2(1600.0, 900.0), false)
	scene.wiki_host.open_page(WikiModel.PLAYER, PLAYER)
	await _frames(4)
	scene.wiki_host.screen.body.scroll_to(0.0)
	await _frames(3)
	_dump("desktop file top", scene.wiki_host.screen)
	await _capture("issue208_desktop_file_top")
	scene.wiki_host.screen.body.scroll_to(330.0)
	await _frames(4)
	_dump("desktop file notes", scene.wiki_host.screen)
	await _capture("issue208_desktop_file_notes")

	var season := LeagueSeason.create("Copy Evidence", "generated", "fixture_days", 208)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	scene.menus.league.show_season(season)
	scene.wiki_host.open_page_over_league(WikiModel.PLAYER, PLAYER)
	await _frames(4)
	scene.wiki_host.screen.body.scroll_to(330.0)
	await _frames(4)
	_dump("desktop season notes", scene.wiki_host.screen)
	await _capture("issue208_desktop_season_notes")

	# A 2400x1080 handset at 420 dpi reads a 1096x493 design space.
	await _design(Vector2(1096.0, 493.0), true)
	scene.wiki_host.screen.open(WikiModel.PLAYER, PLAYER)
	await _frames(4)
	scene.wiki_host.screen.body.scroll_to(330.0)
	await _frames(4)
	_dump("phone season notes", scene.wiki_host.screen)
	await _capture("issue208_phone_season_notes")
	print("EXIT done")
	quit()

func _dump(label: String, screen) -> void:
	var page: Dictionary = screen.page_data if screen != null else {}
	print("PAGE %s title=%s" % [label, str(page.get("title", ""))])
	for block in page.get("blocks", []):
		var kind := str(block.get("k", ""))
		if kind == "section" or kind == "note":
			print("  %s: %s" % [kind.to_upper(), str(block.get("text", ""))])

func _design(vp: Vector2, touch: bool) -> void:
	var scale: float = scene.get_viewport().get_visible_rect().size.x / vp.x
	scene.dev.ui_scale = scale
	scene._sync_overlay_scale()
	scene.touch = touch
	if scene.wiki_host != null:
		scene.wiki_host.screen.touch = touch
		scene.wiki_host.sync_scale()
	await _frames(4)
	print("DESIGN %s scale %.3f touch %s -> %s" % [str(vp), scale, str(touch), str(scene.wiki_host.screen.design_vp())])

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
