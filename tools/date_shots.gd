extends SceneTree

## Evidence capture for issue #99: one date form (`15/AUG/2026`) everywhere, with
## the weekday revealed on hover (or on a held press, on touch).
##
## Boots the real game scene, builds a generated season, walks the surfaces that
## show a date, rests the pointer on that date and writes a PNG into `res://shots/`.
## Run it with a display (not `--headless`: a headless run has no frame to read).
##
##   godot --path . --script res://tools/date_shots.gd

var scene = null
var league = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(5)
	league = scene.menus.league
	var season := LeagueSeason.create("Date Evidence", "generated", "fixture_days", 99)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	league.screen.mouse = Vector2(-1000.0, -1000.0)
	await _capture("issue99_hub_plain")
	await _hover_shot("issue99_hub_hover", league.screen, true)
	league.screen.click("table")
	await _hover_shot("issue99_table_hover", league.screen, true)
	league.screen.click("back")
	league.open_load()
	await _hover_shot("issue99_load_hover", league.screen)
	league.close()
	league.show_season(season)
	league.screen.click("continue")
	await _hover_shot("issue99_roundup_hover", league.screen, true)
	if league.screen.mode == LeagueScreen.MODE_REPORT:
		var first := ""
		for report in league.screen.roundup:
			first = str(report["fixture"]["id"])
			break
		if first != "":
			league.screen.show_report(first)
			await _hover_shot("issue99_report_hover", league.screen)
	# Touch arm: a phone has no hover, so a held press reveals the same weekday.
	league.show_season(season)
	league.screen.touch = true
	league.screen.holding = true
	await _hover_shot("issue99_hub_touch_hold", league.screen, true)
	league.screen.touch = false
	league.screen.holding = false
	# Phone design space: the same hub in the overlay scale a handset uses.
	league.screen.ui_scale = 2.19
	league.screen.refresh()
	await _hover_shot("issue99_hub_phone_hover", league.screen, true)
	league.screen.ui_scale = 1.0
	league.screen.refresh()
	# Encyclopedia surfaces: the snapshot date in the header, then the results
	# table below the fold, whose date cells read in the same form.
	scene.wiki_host.open_page_over_league(WikiModel.LEAGUE, "")
	await _frames(4)
	await _hover_shot("issue99_wiki_snapshot_hover", scene.wiki_host.screen, true)
	scene.wiki_host.screen.body.scroll_to(2000.0)
	await _frames(4)
	await _capture("issue99_wiki_results")
	print("EXIT done")
	quit()

## Rest the pointer on a date strip the sheet painted, then capture. The chrome's
## dates are screen-space; a sheet's rows are read through the body's scroll.
func _hover_shot(name: String, screen, chrome_only: bool = false) -> void:
	await _frames(3)
	var sources: Array = [screen.hints]
	if not chrome_only and screen.rows_hints != null:
		sources = [screen.rows_hints, screen.hints]
	for source in sources:
		var chrome: bool = source == screen.hints
		for zone in (source as DateHints).zones:
			var rect: Rect2 = zone["rect"]
			var point := _screen_point(screen, rect, chrome)
			if not chrome and not _window(screen).has_point(point):
				# The row is scrolled out of the window: bring it into view.
				screen.body.scroll_to(maxf(0.0, rect.get_center().y - screen.body.size.y * 0.5))
				await _frames(3)
				point = _screen_point(screen, rect, false)
			if not chrome and not _window(screen).has_point(point):
				continue
			screen.mouse = point
			await _frames(4)
			var zone_date := str(zone["date"])
			print("HOVER %s date=%s weekday=%s at=%s" % [name, zone_date,
				FixtureCalendar.weekday_label(zone_date), str(point)])
			await _capture(name)
			return
	print("SHOT %s has no date strip in view" % name)

func _window(screen) -> Rect2:
	if screen.body == null:
		return Rect2(Vector2.ZERO, Vector2(4000.0, 4000.0))
	return Rect2(screen.body.position, screen.body.size)

## A strip in screen units. The chrome paints in screen space; a body's rows are
## either body-local (the encyclopedia) or design space (the league sheets).
func _screen_point(screen, rect: Rect2, chrome: bool) -> Vector2:
	var c := rect.get_center()
	if chrome or screen.body == null:
		return c
	if bool(screen.tooltip.rows_local):
		return c + screen.body.position - Vector2(0.0, screen.body.scroll)
	return c - Vector2(screen.body.hscroll, screen.body.scroll)

func _capture(name: String) -> void:
	await _frames(3)
	# The viewport texture only holds the last drawn frame: reading it without
	# waiting for the draw hands back the previous pose (or the same image twice).
	await RenderingServer.frame_post_draw
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
	print("SHOT ", name)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame