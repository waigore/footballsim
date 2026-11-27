extends SceneTree

## Evidence capture for #309: on a real-fixture season every pending fixture on
## the hub started 60 design units in, so a blank kick-off gutter sat where a
## time would be and the clubs jumped 52 units left when the row became a result.
##
## Boots the real scene, creates a season from the real fixture snapshot (the
## default the New League wizard offers), shoots TODAY'S FIXTURES at a 1600x900
## and a 3024x1648 window, then watches that day's fixture to full time and
## shoots the same row again as the result block it becomes.
##
## The shots are read back, not eyeballed: for the day's first plan row it scans
## the frame's pixels and prints the first ink column and the club-name strips'
## design x, so the gutter (and its absence) is a measured number at every pose.
##
##   xvfb-run -a godot --path . --script res://tools/issue309_shots.gd
##
## Writes PNGs into `res://shots/` (git-ignored) and prints the measurements.

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Gutter 309", "real", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a real-fixture season")
		quit()
		return
	league.show_season(season)
	await _frames(3)
	print("DAY ", str(league.screen.current_view().get("date", "")),
		" calendar=", str(season.rules.get("calendar_mode", "")))
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		var tag := "%dx%d" % [size.x, size.y]
		var name := "issue309_hub_pending_%d" % size.x
		await _shot(name)
		_measure(league, tag + " pending", name)
	# Watch the day's first fixture and play it to the whistle, then read the
	# same row as the result block it becomes.
	var fixture := _first_fixture(league)
	print("WATCH ", fixture)
	league.screen.click("toggle:" + fixture)
	print("TOGGLE watched=", str(league.screen.current_view()["plan"][0].get("watched", "?")))
	league.screen.click("continue")
	await _frames(2)
	print("AFTER CONTINUE watch=", league.watch, " mode=", league.screen.mode,
		" engine=", scene.engine.phase if scene.engine != null else "none")
	_kick_briefing()
	await _frames(2)
	scene.engine.half = 2
	scene.engine.clock = 5399.0
	scene.engine.added[1] = 0.0
	var guard := 0
	while scene.engine.phase != "full_time" and guard < 400:
		scene._advance_ticks(600)
		scene._post_tick()
		if scene.engine.phase == "half_time":
			scene.engine.begin_second_half()
		guard += 1
	scene._process(0.016)
	await _frames(3)
	print("WHISTLE phase=", scene.engine.phase, " holding=", league.is_holding())
	# Dismiss the FULL TIME card: the hub comes back on the same day, the row now
	# a result (#124).
	if league.is_holding():
		league.result.dismiss()
	await _frames(4)
	print("BACK mode=", league.screen.mode, " day=", str(league.screen.current_view().get("date", "")))
	for fx in league.screen.current_view().get("plan", []):
		print("PLAN ", str(fx.get("id", "")), " status=", str(fx.get("status", "")),
			" goals=", str(fx.get("home_goals", "")), "-", str(fx.get("away_goals", "")))
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		var tag := "%dx%d" % [size.x, size.y]
		var name := "issue309_hub_played_%d" % size.x
		await _shot(name)
		_measure(league, tag + " played", name, "fixture:" + fixture)
	# A generated season does print a kick-off time, so the measured rail is
	# shown beside the empty one: the time prints, and the clubs start past it.
	var generated := LeagueSeason.create("Timed 309", "generated", "fixture_days", 2026)
	if generated != null:
		league.show_season(generated)
		await _frames(3)
		await _pose(Vector2i(1600, 900))
		await _shot("issue309_hub_timed_1600")
		_measure(league, "1600x900 timed", "issue309_hub_timed_1600")
	print("EXIT season=", season.save.slug)
	quit()

func _first_fixture(league: LeagueHost) -> String:
	for fx in league.screen.current_view().get("plan", []):
		if str((fx as Dictionary).get("status", "")) != "played":
			return str(fx["id"])
	return ""

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

## Read the day's first plan row out of the frame: the leftmost column that is not
## the row's own panel fill, and where its club strips really start.
func _measure(league: LeagueHost, tag: String, shot: String, wants: String = "") -> void:
	var row := {}
	for item in league.screen.buttons:
		if str(item["kind"]) != "row" or not str(item["id"]).begins_with("fixture:"):
			continue
		if wants == "" or str(item["id"]) == wants:
			row = item
			break
	if row.is_empty():
		print("MEASURE %s skipped (no plan row on screen)" % tag)
		return
	var rect: Rect2 = row["rect"]
	var fx: Dictionary = row["fixture"]
	var strip := -1.0
	for zone in league.screen.hub.plan.names.zones:
		if str(zone["club_id"]) == str(fx.get("home_club_id", "")):
			strip = (zone["rect"] as Rect2).position.x
			break
	print("GEOMETRY %s status=%s kick_off='%s' row_x=%.1f clubs_x=%.1f" % [
		tag, str(fx.get("status", "")), str(fx.get("kickoff_time", "")),
		rect.position.x, strip])
	var img := _load_shot(shot)
	if img == null:
		print("MEASURE %s skipped (no shot)" % tag)
		return
	var scale: float = maxf(scene.chrome_scale, 0.001)
	scale *= float(img.get_height()) / maxf(root.get_visible_rect().size.y, 1.0)
	# The row's own empty fill, read from just inside its left edge.
	var y0 := int(round((rect.position.y + 6.0) * scale))
	var y1 := int(round((rect.end.y - 6.0) * scale))
	var mid := int(round((rect.position.y + rect.size.y * 0.5) * scale))
	var empty: Color = img.get_pixel(int(round((rect.position.x + 2.0) * scale)), mid)
	var ink := -1
	var x1 := int(round((rect.end.x - 84.0) * scale))
	# Start past the row's own panel edge, so the first ink is copy, not border.
	var x0 := int(round((rect.position.x + 4.0) * scale))
	for x in range(x0, x1 + 1):
		var painted := 0
		for y in range(y0, y1 + 1):
			if not _near(img.get_pixel(x, y), empty, 0.05):
				painted += 1
		if painted > 0:
			ink = x
			break
	print("MEASURE %s first_ink_px=%d first_ink_design=%.1f row_x_design=%.1f" % [
		tag, ink, float(ink) / scale if ink >= 0 else -1.0, rect.position.x])

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

## CONTINUE on the pre-match briefing, so the watched fixture really kicks off.
func _kick_briefing() -> void:
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")

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
