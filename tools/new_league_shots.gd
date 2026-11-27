extends SceneTree

## Evidence capture for the New League sheet on a short viewport (#372).
##
## Boots the real game scene, opens NEW LEAGUE, and shoots the sheet at the
## handset design space before and after a drag, then at a desktop window:
##
##   * `n372_new_league_phone` — the door bar pinned at the foot, the league
##     list scrolling between the header and CREATE SEASON,
##   * `n372_new_league_phone_scrolled` — the last country groups and the bar,
##   * `n372_new_league_short` — the same at a 360-unit sheet,
##   * `n372_new_league_desktop` — the whole form in the flow, no bar.
##
## Each pose prints the geometry it shot, so the numbers are checked as well as
## the pixels. Writes a PNG per pose into `res://shots/`.
##
##   godot --path . --resolution 1600x900 --script res://tools/new_league_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.league.open_wizard()
	await _frames(3)
	await _phone()
	_print_sheet("phone")
	await _shot("n372_new_league_phone")
	var screen = scene.menus.league.screen
	screen.body.scroll_to(screen.body.max_scroll())
	await _frames(2)
	await _shot("n372_new_league_phone_scrolled")
	await _short()
	screen.body.scroll_to(0.0)
	await _frames(2)
	_print_sheet("short")
	await _shot("n372_new_league_short")
	await _desktop()
	screen.body.scroll_to(0.0)
	await _frames(2)
	_print_sheet("desktop")
	await _shot("n372_new_league_desktop")
	print("EXIT vp=%s" % scene.get_viewport().get_visible_rect().size)
	quit()

func _print_sheet(label: String) -> void:
	var screen = scene.menus.league.screen
	var vp: Vector2 = screen.design_vp()
	var parts: Array = []
	for item in screen.buttons:
		var id := str(item["id"])
		if id != "create" and id != "back" and not id.begins_with("wleague:"):
			continue
		var rect: Rect2 = item["rect"]
		parts.append("%s=%.0fx%.0f@%.0f,%.0f" % [id, rect.size.x, rect.size.y, rect.position.x, rect.position.y])
	print("NEWLEAGUE %s vp=%s body=%s scroll=%.1f max=%.1f cue=%s pinned=%d %s" % [label, str(vp),
		str(Rect2(screen.body.position, screen.body.size)), screen.body.scroll,
		screen.body.max_scroll(), str(screen.body.more_below()), screen.body.pinned.size(),
		_doors_line(parts)])

func _doors_line(parts: Array) -> String:
	if parts.size() > 8:
		parts = parts.slice(0, 5) + ["…"] + parts.slice(parts.size() - 2)
	return " ".join(PackedStringArray(parts))

func _phone() -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 411.0, 1.0)
	scene._sync_overlay_scale()
	await _refresh()

func _short() -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 360.0, 1.0)
	scene._sync_overlay_scale()
	await _refresh()

func _desktop() -> void:
	scene.dev.ui_scale = 0.0
	scene.touch = false
	scene._sync_overlay_scale()
	await _refresh()

func _refresh() -> void:
	await _frames(2)
	var league: LeagueHost = scene.menus.league
	if league.screen != null and league.screen.is_open():
		league.sync(Transform2D.IDENTITY.scaled(Vector2(scene.chrome_scale, scene.chrome_scale)),
			scene.chrome_scale, scene.touch)
		league.screen.refresh()
	await _frames(2)

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
	img.save_png("res://shots/%s.png" % name)
	print("SHOT shots/%s.png %s" % [name, img.get_size()])
