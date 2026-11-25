extends SceneTree

## Evidence capture for the god-mode season surfaces.
##
## Boots the real game scene, builds a generated season, walks the hub, the
## table, the calendar, a roundup, a single report and the podium, and writes a
## PNG per pose into `res://shots/`. Run it on a display (or `xvfb-run`) — a
## headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/league_shots.gd
##
## The season it creates lives in `user://saves` like any other save.

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	league.open_wizard()
	await _shot("league_wizard")
	league.close()
	var season := LeagueSeason.create("Evidence Season", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	# Eight rounds so the table has a shape worth reading.
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	print("DBG layer=", league.layer.visible, " screen=", league.screen.visible, " mode=", league.screen.mode, " open=", league.is_open(), " scale=", league.screen.ui_scale)
	await _shot("league_hub")
	league.screen.click("table")
	await _shot("league_table")
	league.screen.click("back")
	league.screen.click("calendar")
	await _shot("league_calendar")
	league.screen.click("back")
	league.screen.click("continue")
	await _shot("league_roundup")
	if league.screen.mode == LeagueScreen.MODE_REPORT:
		var first := ""
		for report in league.screen.roundup:
			first = str(report["fixture"]["id"])
			break
		if first != "":
			league.screen.show_report(first)
			await _shot("league_report")
		league.screen.click("back")
	# Finish the season for the podium.
	guard = 0
	while season.matches_remaining() > 0 and guard < 60:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("league_podium")
	print("EXIT season=", season.save.slug, " champion=", str(season.summary().get("champion", {}).get("club", "")))
	quit()

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
	print("SHOT ", name)
