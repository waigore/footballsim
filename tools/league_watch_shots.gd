extends SceneTree

## Evidence capture for issue #100: Continue opens the watched fixture, and a
## watched match the player walks out of is finished at speed and saved.
##
## Boots the real game scene, builds a generated season, flags one fixture,
## shoots the hub with `CONTINUE OPENS THE NEXT WATCH`, opens it with Continue,
## leaves with MENU, shoots the hub while the match finishes, then shoots the
## saved result and its report. Writes a PNG per pose into `res://shots/`.
## Run it on a display (or under `xvfb-run`); a headless run has no frame to
## read back.
##
##   xvfb-run -a godot --path . --script res://tools/league_watch_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Watch Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var plan: Array = league.screen.current_view()["plan"]
	var held := str(plan[0]["id"])
	league.screen.click("toggle:" + held)
	await _shot("issue-100-hub-watch")
	print("HUB pending=", held, " watch chip=", int(league.screen.current_view()["plan"][0]["watched"]))
	league.screen.click("continue")
	await _frames(2)
	print("CONTINUE viewer paused=", scene.paused, " home=", scene.home_id, " away=", scene.away_id,
		" watching=", season.watching_fixture)
	await _shot("issue-100-viewer")
	# Leave before full time: the hub comes back and the match finishes behind it.
	scene.menus.open_menu()
	await _frames(2)
	print("LEAVE settling=", league.watch.settling(), " hub finishing=", league.screen.current_view().get("settling", false))
	await _shot("issue-100-finishing")
	var guard := 0
	while league.watch.settling() and guard < 40000:
		league.watch.tick()
		guard += 1
	var stored: Dictionary = season.report(held)
	print("FINISHED slices=", guard, " settling=", league.watch.settling(), " played=", stored["played"],
		" score=", stored["score"])
	await _shot("issue-100-hub-result")
	league.screen.show_report(held)
	await _shot("issue-100-report")
	print("EXIT ok fixture=", held)
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
