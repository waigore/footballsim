extends SceneTree

## Evidence capture for #308: in the desktop (FULL) league table the place number
## was painted from the row's own left edge, the same x the coloured zone band is
## drawn at, so ranks 1–6 — the rows a player reads first — carried their digit
## strokes inside the band.
##
## Boots the real game scene, builds a generated season, plays enough rounds that
## the table has a shape, opens the season's TABLE sheet on its full reading and
## shoots it at a 1600x900 and a 3024x1648 window. The shot is read back, not
## eyeballed: for the first banded row it scans the frame's pixels and prints the
## zone band's columns and the place digit's ink columns, so clearance is a
## measured number at every window size.
##
##   xvfb-run -a godot --path . --script res://tools/issue308_shots.gd
##
## Writes PNGs into `res://shots/` (git-ignored) and prints the measurements.

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Place Band 308", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	league.screen.click("table")
	await _frames(3)
	print("READING mode=", league.screen.book.table.mode)
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		var tag := "%dx%d" % [size.x, size.y]
		var name := "issue308_table_full_%d" % size.x
		await _shot(name)
		_measure(league, tag, name)
	print("EXIT season=", season.save.slug)
	quit()

## Give the window a real size, then let the scene re-derive every overlay scale
## for it exactly as a resize would.
func _pose(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	await _frames(4)
	scene._sync_overlay_scale()
	scene.menus.league.screen.refresh()
	await _frames(4)
	print("WINDOW ", DisplayServer.window_get_size(), " chrome_scale=", scene.chrome_scale,
		" design_vp=", scene.menus.league.screen.design_vp())

## Read the first banded row out of the frame: the band's pixel columns and the
## place digit's ink columns, both measured from the image the engine drew.
func _measure(league: LeagueHost, tag: String, shot: String) -> void:
	var img := _load_shot(shot)
	if img == null:
		print("MEASURE %s skipped (no shot)" % tag)
		return
	var scale: float = maxf(scene.chrome_scale, 0.001)
	# A window whose size is not the viewport's own (Godot's `canvas_items`
	# stretch scales the drawing up) needs one more factor: the image is window
	# pixels, the design space is viewport units.
	scale *= float(img.get_height()) / maxf(root.get_visible_rect().size.y, 1.0)
	var row := {}
	for item in league.screen.buttons:
		if str(item["kind"]) == "table_row" and str(item["zone"]) != "":
			row = item
			break
	if row.is_empty():
		print("MEASURE %s skipped (no banded row on screen)" % tag)
		return
	var rect: Rect2 = row["rect"]
	var places: Dictionary = row["places"]
	var band: Color = LeagueChrome.zone_color(str(row["zone"]))
	var ink := UiChrome.C_DIM
	# Pixel window: the band plus the place column, in the row's own middle.
	var y0 := int(round((rect.position.y + 5.0) * scale))
	var y1 := int(round((rect.end.y - 5.0) * scale))
	var x0 := int(round(rect.position.x * scale))
	var x1 := int(round((float(places["club_x"]) - 1.0) * scale))
	var band_cols: Array = []
	var ink_cols: Array = []
	for x in range(x0, x1 + 1):
		var saw_band := false
		var saw_ink := false
		for y in range(y0, y1 + 1):
			var p: Color = img.get_pixel(x, y)
			if _near(p, band, 0.10):
				saw_band = true
			elif _near(p, ink, 0.30) and not _near(p, band, 0.30):
				saw_ink = true
		if saw_band:
			band_cols.append(x)
		if saw_ink:
			ink_cols.append(x)
	var band_span := _span(band_cols)
	var ink_span := _span(ink_cols)
	var clear: bool = ink_span[0] > band_span[1] if ink_span[0] >= 0 and band_span[1] >= 0 else false
	print("MEASURE %s rank=%d zone=%s band_px=[%d,%d] place_ink_px=[%d,%d] clear=%s" % [
		tag, int((row["row"] as Dictionary)["position"]), str(row["zone"]),
		band_span[0], band_span[1], ink_span[0], ink_span[1], str(clear)])
	print("GEOMETRY %s band_design=[%.1f,%.1f] place_x=%.1f club_x=%.1f" % [
		tag, rect.position.x, rect.position.x + LeagueTableView.ZONE_BAND_W,
		float(places["pos_x"]), float(places["club_x"])])

func _span(cols: Array) -> Array:
	if cols.is_empty():
		return [-1, -1]
	return [int(cols[0]), int(cols[cols.size() - 1])]

## A pixel close enough to `want` to count as that paint, with antialiasing
## allowed for.
func _near(p: Color, want: Color, tol: float) -> bool:
	return absf(p.r - want.r) <= tol and absf(p.g - want.g) <= tol and absf(p.b - want.b) <= tol

func _load_shot(name: String) -> Image:
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
	if not FileAccess.file_exists(path):
		return null
	return Image.load_from_file(path)

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
	print("SHOT ", name, " ", img.get_size())
