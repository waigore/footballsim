extends SceneTree

## Evidence capture for issue #171: an AUTO report can show a penalty goal.
##
## Boots the real game scene, builds a generated season, settles matchdays until
## one played report carries a tagged penalty, then shoots:
##
##   * the match report on a desktop window,
##   * the day's results / roundup rows,
##   * the same report and roundup at the phone design space,
##   * the generated AUTO clip of that penalty, mid spot kick.
##
## Writes a PNG per pose into `res://shots/`. Run it on a display; a headless run
## has no frame to read back.
##
##   godot --path . --script res://tools/league_penalty_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Penalty Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var reports: Array = []
	var pen_fx := ""
	var pen_index := -1
	var pen_minute := 0
	var pen_name := ""
	var guard := 0
	while pen_fx == "" and guard < 8:
		var result := season.advance()
		reports = result.get("played", [])
		for report in reports:
			for row in report.get("highlights", []):
				if int(row.get("penalty", 0)) == 1:
					pen_fx = str(report["fixture"]["id"])
					pen_index = int(row["goal_index"])
					pen_minute = int(row["minute"])
					pen_name = str(row["scorer_name"])
					break
			if pen_fx != "":
				break
		guard += 1
	if pen_fx == "":
		print("EXIT no penalty in the first %d matchdays" % guard)
		quit()
		return
	for e in season.report(pen_fx)["events"]:
		if str(e["kind"]) == "goal":
			print("GOAL %s' %s penalty=%s" % [e["minute"], e.get("player_name", ""), e.get("penalty", 0)])
	print("PENALTY fixture=%s goal_index=%d minute=%d scorer=%s" % [pen_fx, pen_index, pen_minute, pen_name])
	league.screen.show_report(pen_fx)
	await _shot("issue-171-report-desktop")
	league.screen.show_roundup(reports)
	await _shot("issue-171-roundup-desktop")
	# Phone design space: scale the league layer so the compact sheet is chosen.
	await _width(league, 913.0)
	league.screen.show_report(pen_fx)
	await _shot("issue-171-report-phone")
	league.screen.show_roundup(reports)
	await _shot("issue-171-roundup-phone")
	# Play the generated clip of that penalty. The strike lands early in the
	# vignette, so the shots bracket the spot kick.
	await _width(league, 1280.0)
	league.screen.show_report(pen_fx)
	league.screen.click("goal:%d" % pen_index)
	await _frames(45)
	_report_replay("setup")
	await _shot("issue-171-clip-setup")
	await _frames(120)
	_report_replay("strike")
	await _shot("issue-171-clip-strike")
	await _frames(55)
	_report_replay("net")
	await _shot("issue-171-clip-net")
	await _frames(40)
	_report_replay("goal")
	await _shot("issue-171-clip-goal")
	print("EXIT ok fixture=", pen_fx, " index=", pen_index)
	quit()

func _width(league: LeagueHost, design_width: float) -> void:
	var scale := maxf(league.screen.size.x / design_width, 1.0)
	scene.hud_scale = scale
	league.sync(Transform2D.IDENTITY.scaled(Vector2(scale, scale)), scale, false)
	league.screen.refresh()
	await _frames(3)
	print("DESIGN VP ", league.screen.design_vp(), " window ", league.screen.size, " scale ", scale)

func _report_replay(label: String) -> void:
	var rp = scene.replay
	print("REPLAY %s active=%s paused=%s menus=%s speed=%.2f t=%.2f len=%.2f" % [label,
		str(rp != null), str(scene.paused), str(scene.menus.active()), float(scene.speed),
		float(rp.t) if rp != null else -1.0, float(rp.length) if rp != null else -1.0])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(4)
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
