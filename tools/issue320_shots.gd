extends SceneTree

## Evidence capture for #320: on the Match Report sheet each club's column
## caption sat on the first event line, because the rows began at `HEADER + 70`
## while the captions painted at `HEADER + 72`.
##
## Boots the real scene, creates a generated season, plays a matchday and opens
## the report of the fixture with the most events at 1600x900 and 3024x1648. It
## prints the caption band, the first row on each side and the whole column's
## tops, so the separation is a measured number rather than an impression.
##
##   xvfb-run -a godot --path . --script res://tools/issue320_shots.gd
##
## Writes PNGs into `res://shots/` (git-ignored).

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	if league == null:
		print("EXIT no league host")
		quit()
		return
	var season := LeagueSeason.create("Report Captions 320", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	await _frames(3)
	# A played day gives every fixture a report with goals and cards in it.
	season.advance()
	var picked := _busiest_fixture(season)
	if picked == "":
		print("EXIT no played fixture with events")
		quit()
		return
	league.show_season(season)
	await _frames(3)
	# The UX catalogue grades the league-hub surface, whose CONTINUE is the flow
	# screen's named CTA; the report is shot beside it on the evidence page.
	await _shot("issue320_hub_1600")
	league.screen.show_report(picked)
	await _frames(4)
	print("REPORT fixture=", picked, " ", _read(league.screen))
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		print("REPORT %dx%d %s" % [size.x, size.y, _read(league.screen)])
		await _shot("issue320_report_%d" % size.x)
	league.screen.click("back")
	await _frames(2)
	print("EXIT season=", season.save.slug)
	quit()

## The fixture of the last played day whose report carries the most events.
func _busiest_fixture(season) -> String:
	var best := ""
	var most := -1
	for date in season.record.fixtures.dates():
		for fx in season.record.fixtures.on(date):
			if str(fx.get("status", "")) != "played":
				continue
			var n: int = (season.report(str(fx["id"])).get("events", []) as Array).size()
			if n > most:
				most = n
				best = str(fx["id"])
	return best

## The caption band and every event row's top, read from the rows the sheet laid.
func _read(screen) -> String:
	var tops := {"home": [], "away": []}
	for item in screen.buttons:
		if str(item.get("kind", "")) != "event":
			continue
		var side := str(item.get("side", ""))
		(tops[side] as Array).append((item["rect"] as Rect2).position.y)
	return "caption=%.1f first_home=%.1f first_away=%.1f home=%s away=%s" % [
		LeagueReportSheet.CAPTION_Y,
		float(tops["home"][0]) if not (tops["home"] as Array).is_empty() else -1.0,
		float(tops["away"][0]) if not (tops["away"] as Array).is_empty() else -1.0,
		_row_tops(tops["home"]), _row_tops(tops["away"])]

func _row_tops(rows: Array) -> String:
	var out: Array = []
	for y in rows:
		out.append("%.0f" % float(y))
	return "[%s]" % ", ".join(PackedStringArray(out))

## Set the window the shot is taken in, then settle the shell on it.
func _pose(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	await _frames(4)
	scene._sync_overlay_scale()
	await _frames(4)

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
