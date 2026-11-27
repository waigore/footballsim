extends SceneTree

## Evidence capture for the phone's tap targets (#369).
##
## Boots the real game scene and shoots, in the handset design space, the
## controls a thumb has to hit to choose and run a match:
##
##   * the fixture picker's league chips and ALLOW DRAW / EXTRA TIME & PENS,
##   * the league hub's fixture rows, their AUTO / WATCH doors and SUGGEST
##     WATCHES,
##   * the pre-match briefing's BACK and KICK OFF,
##   * the encyclopedia's BACK and close doors.
##
## Each pose prints the geometry it shot, so the numbers are checked as well as
## the pixels. Writes a PNG per pose into `res://shots/`.
##
##   godot --path . --resolution 1600x900 --script res://tools/tap_target_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	print("WINDOW vp=%s hud=%.2f chrome=%.2f touch=%s" % [str(scene.get_viewport_rect().size),
		scene.hud_scale, scene.chrome_scale, str(scene.touch)])
	await _picker()
	await _hub()
	await _briefing()
	await _wiki()
	print("EXIT touch=%s scale=%.2f" % [str(scene.touch), scene.hud_scale])
	quit()

func _picker() -> void:
	await _phone()
	scene.open_select(true)
	await _frames(2)
	await _shot("tap369_picker_411")
	_print_picker("411")
	await _short()
	await _frames(2)
	await _shot("tap369_picker_360")
	_print_picker("360")
	await _desktop()
	scene.selector.click("back")
	await _frames(2)

func _hub() -> void:
	var league: LeagueHost = scene.menus.league
	await _phone()
	var season := LeagueSeason.create("Tap Target Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("HUB no season")
		return
	league.show_season(season)
	await _frames(3)
	league.screen.refresh()
	await _frames(2)
	await _shot("tap369_hub_411")
	_print_hub("411")
	await _short()
	league.screen.refresh()
	await _frames(2)
	await _shot("tap369_hub_360")
	_print_hub("360")
	await _desktop()
	league.detach_season()
	league.close()
	await _frames(2)

func _briefing() -> void:
	await _phone()
	scene.open_select(true)
	await _frames(2)
	scene.selector.click("confirm")
	await _frames(3)
	await _shot("tap369_briefing_411")
	var screen = scene.prematch.screen
	if screen != null and screen.is_open():
		var lay: Dictionary = screen.layout(screen.design_vp())
		var parts: Array = []
		for b in lay["buttons"]:
			parts.append("%s=%s" % [str(b["id"]), str(b["rect"])])
		print("BRIEFING %s" % " ".join(PackedStringArray(parts)))
		screen.click("back")
	await _frames(2)
	scene.selector.click("back")
	await _desktop()
	await _frames(2)

func _wiki() -> void:
	scene.menus.close()
	await _frames(2)
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _frames(3)
	await _phone()
	await _shot("tap369_wiki_411")
	var f: float = 0.0
	var c: float = 0.0
	for b in scene.wiki_host.screen.buttons:
		if str(b["id"]) == "back":
			f = (b["rect"] as Rect2).size.y
		elif str(b["id"]) == "close":
			c = (b["rect"] as Rect2).size.y
	print("WIKI back_h=%.1f close_h=%.1f vp=%s" % [f, c, str(scene.wiki_host.screen.design_vp())])
	scene.wiki_host.close()
	await _desktop()
	await _frames(2)

func _print_picker(label: String) -> void:
	var picker = scene.selector
	var vp: Vector2 = picker.design_vp()
	var heights: Array = []
	for b in picker.buttons:
		var id := str(b["id"])
		if id.begins_with("league:") or id.begins_with("win:"):
			heights.append("%s=%.1f" % [id, (b["rect"] as Rect2).size.y])
	var band: Rect2 = LeagueChrome.picker_chips_band(vp, true)
	print("PICKER %s vp=%s chips=%s band=%s" % [label, str(vp),
		" ".join(PackedStringArray(heights)), str(band)])

func _print_hub(label: String) -> void:
	var screen = scene.menus.league.screen
	var vp: Vector2 = screen.design_vp()
	var rows: Array = []
	for b in screen.buttons:
		if (b["rect"] as Rect2).size.y > 0.0 and str(b["id"]).begins_with("fixture:"):
			rows.append("%s=%.1f" % [str(b["id"]), (b["rect"] as Rect2).size.y])
	var chips: Array = []
	for b in screen.buttons:
		if str(b["id"]).begins_with("toggle:"):
			chips.append("%.1f" % (b["rect"] as Rect2).size.y)
	print("HUB %s vp=%s mode=%s rows=%s toggles=%s" % [label, str(vp), screen.mode,
		" ".join(PackedStringArray(rows.slice(0, 2))),
		" ".join(PackedStringArray(chips.slice(0, 2)))])

func _phone() -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 411.0, 1.0)
	scene._sync_overlay_scale()
	await _frames(2)

func _short() -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 360.0, 1.0)
	scene._sync_overlay_scale()
	await _frames(2)

func _desktop() -> void:
	scene.dev.ui_scale = 1.0
	scene._sync_overlay_scale()
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
