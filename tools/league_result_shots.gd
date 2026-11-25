extends SceneTree

## Evidence capture for issue #124: a watched fixture shows its full-time card,
## and the hub afterwards keeps that day with `FT` and the scores.
##
## Boots the real game scene, builds a generated season, marks one fixture to
## watch, reaches full time, shoots the held FULL TIME card, dismisses it with
## the key a desktop player reaches for, shoots the hub of the played day and
## the result's report. Writes a PNG per pose into `res://shots/`. Run it on a
## display (or under `xvfb-run`); a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/league_result_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Result Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var day := str(season.state()["date"])
	var held := str(league.screen.current_view()["plan"][0]["id"])
	league.screen.click("toggle:" + held)
	# The main door settles the day's AUTO fixtures and hands over the watch, so
	# the day ends up mixed: nine results and the match being watched.
	league.screen.click("continue")
	_kick_briefing()
	await _frames(2)
	print("WATCH date=", day, " fixture=", held, " viewer=", scene.home_id, " v ", scene.away_id,
		" paused=", scene.paused)
	await _shot("issue-124-viewer")
	# Park the match a minute short of full time: the whistle is the engine's own.
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
	print("WHISTLE phase=", scene.engine.phase, " score=", scene.engine.score,
		" holding=", league.is_holding(), " result_hold=", scene.result_hold,
		" hud=", scene.hud_layer.visible, " paused=", scene.paused)
	await _shot("issue-124-full-time-card")
	# The key a desktop player reaches for hands the season back.
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	scene._input(key)
	await _frames(2)
	var stored: Dictionary = season.report(held)
	print("HUB date=", season.state()["date"], " holding=", league.is_holding(),
		" hub_open=", league.is_open(), " played=", stored.get("played", false),
		" score=", stored.get("score", []))
	var doors: Array = []
	for item in league.screen.buttons:
		doors.append(str(item["id"]))
	print("HUB doors=", ", ".join(doors))
	await _shot("issue-124-hub-result")
	league.screen.show_report(held)
	await _shot("issue-124-report")
	print("EXIT ok fixture=", held)
	quit()

## Every watched match now opens the pre-match briefing first (#157): kick it off
## so the pose this tool captures is the match, not the briefing.
func _kick_briefing() -> void:
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")

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
	print("SHOT ", name, " ", img.get_size())
