extends SceneTree

## Evidence capture for #309: on a real-fixture season every pending row on the
## hub printed its clubs 60 design units in, leaving a blank kick-off slot where
## a time would be — and the result block that replaces the row at the whistle
## starts its names at the row's own inset, so the day jumped left at full time.
##
## Boots the real game scene, creates a real-fixture save, opens the season hub on
## the first day with a fixture pending and shoots the hub at a 1600x900 and a
## 3024x1648 window. Then it plays that fixture to full time and shoots the same
## row as a result block.
##
## The shot is read back, not eyeballed: for the pending row and for the played
## block it scans the frame's pixels for the first column carrying ink, and
## prints both in design units, so the gutter and the jump are measured numbers.
##
##   xvfb-run -a godot --path . --script res://tools/issue309_shots.gd
##
## Writes PNGs into `res://shots/` (git-ignored) and prints the measurements.

var scene = null
var season = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	season = LeagueSeason.create("Kick-off Gutter 309", "real", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	await _frames(4)
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		var tag := "%dx%d" % [size.x, size.y]
		var name := "issue309_hub_pending_%d" % size.x
		await _shot(name)
		_measure(league, tag + " pending", name, "pending")
	# A generated season does carry a kick-off time: the row must still print it,
	# with the clubs starting after the glyphs rather than at a fixed gutter.
	season.close()
	season = LeagueSeason.create("Kick-off Time 309", "generated", "fixture_days", 2026)
	league.show_season(season)
	await _frames(4)
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		var tag := "%dx%d" % [size.x, size.y]
		var name := "issue309_hub_time_%d" % size.x
		await _shot(name)
		_measure(league, tag + " timed", name, "pending")
	season.close()
	season = LeagueSeason.create("Kick-off Gutter 309", "real", "fixture_days", 2026)
	league.show_season(season)
	await _frames(4)
	# Play the day's fixture: the same row is a result block at the whistle.
	var day: String = season.save.current_date()
	var res: Dictionary = season.advance()
	print("ADVANCE day=", day, " played_today=", (res.get("played", []) as Array).size())
	# Read the day that was just played, so the hub prints its result block.
	season.save.set_date(day)
	league.show_season(season)
	await _frames(4)
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		var tag := "%dx%d" % [size.x, size.y]
		var name := "issue309_hub_played_%d" % size.x
		await _shot(name)
		_measure(league, tag + " played", name, "played")
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

## Read the plan row out of the frame: the row's left edge and the first pixel
## column that carries ink, both in design units.
func _measure(league: LeagueHost, tag: String, shot: String, want: String) -> void:
	var img := _load_shot(shot)
	if img == null:
		print("MEASURE %s skipped (no shot)" % tag)
		return
	var scale: float = maxf(scene.chrome_scale, 0.001)
	scale *= float(img.get_height()) / maxf(root.get_visible_rect().size.y, 1.0)
	var row := {}
	for item in league.screen.buttons:
		if str(item["kind"]) != "row":
			continue
		var fx: Dictionary = item["fixture"]
		if (want == "played") != (str(fx.get("status", "")) == "played"):
			continue
		row = item
		break
	if row.is_empty():
		print("MEASURE %s skipped (no %s row on screen)" % [tag, want])
		return
	var rect: Rect2 = row["rect"]
	var fx: Dictionary = row["fixture"]
	# The club names are the row's only bright ink: the panel, its border and the
	# kick-off / FT caption are all darker, so the first column carrying C_TEXT
	# is where the home name starts — the column that used to jump at the whistle.
	var ink := UiChrome.C_TEXT
	var y0 := int(round((rect.position.y + 3.0) * scale))
	var y1 := int(round((rect.end.y - 3.0) * scale))
	var x0 := int(round(rect.position.x * scale))
	var x1 := int(round((rect.position.x + 200.0) * scale))
	var ink_from := -1
	for x in range(x0, x1 + 1):
		var saw := false
		for y in range(y0, y1 + 1):
			if _near(img.get_pixel(x, y), ink, 0.14):
				saw = true
				break
		if saw:
			ink_from = x
			break
	var first_design := float(ink_from) / scale if ink_from >= 0 else -1.0
	print("MEASURE %s fixture=%s kickoff='%s' row_x=%.1f club_ink_px=%d club_ink_design=%.1f" % [
		tag, str(fx["id"]), str(fx.get("kickoff_time", "")), rect.position.x,
		ink_from, first_design])
	print("ROW %s rect=%s" % [tag, str(rect)])

func _near(a: Color, b: Color, tol: float) -> bool:
	return absf(a.r - b.r) <= tol and absf(a.g - b.g) <= tol and absf(a.b - b.b) <= tol

func _load_shot(name: String) -> Image:
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % name)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load(path) != OK:
		return null
	return img

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
