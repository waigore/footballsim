extends SceneTree

## Evidence capture for issue #167: fixture names, under-team events with icons,
## and the league BACK stack.
##
## Boots the real game scene, builds a generated season, walks a played day, and
## writes a PNG per pose into `res://shots/`. Run it on a display (a headless run
## has no frame to read back):
##
##   godot --path . --script res://tools/league_fixture_shots.gd
##   godot --path . --resolution 913x411 --script res://tools/league_fixture_shots.gd
##
## The second form is the phone-sized design space. The run prints the BACK door
## it found on each pose (enabled / disabled) beside the shot name.

const PREFIX := "issue-167"

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("%s Evidence" % PREFIX, "generated", "fixture_days", 167)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	for i in range(6):
		season.advance()
	var day := _played_day(season)
	if day == "":
		print("EXIT no played day")
		quit()
		return
	# Put the clock back on a played day so the hub can show its results; this is
	# a reading pose, not a gameplay step.
	var rows: Array = season.record.fixtures.on(day)
	season.save.set_date(day)
	season.save.set_matchday(int((rows[0] as Dictionary).get("matchday", 1)))
	season.record.report.memo.clear()
	# A hand-added injury, red card and own goal so every mark the row knows is
	# painted: the auto report writes goals, assists and cards, and an own goal
	# only ever comes off the pitch. Their minutes sit after the fixture's own
	# goals, so the stored clips keep their ordinals.
	var extra: Dictionary = rows[0]
	var home_id := str(extra["home_club_id"])
	var away_id := str(extra["away_club_id"])
	season.record.report.add_events([
		{"fixture_id": str(extra["id"]), "minute": 88, "kind": "injury", "player_id": "",
			"club_id": home_id, "detail": "R. Turner"},
		{"fixture_id": str(extra["id"]), "minute": 89, "kind": "red", "player_id": "",
			"club_id": home_id, "detail": "T. Mitchell"},
		# Credited to the side that gained it, as the report must read.
		{"fixture_id": str(extra["id"]), "minute": 90, "kind": "own_goal", "player_id": "",
			"club_id": away_id, "detail": "M. Okafor"},
	])
	season.record.report.save_result(str(extra["id"]), int(extra["home_goals"]),
		int(extra["away_goals"]) + 1, home_id, away_id, null)
	league.show_season(season)
	await _shot("hub")
	screen_pose(league)
	league.screen.click("calendar")
	await _shot("calendar")
	screen_pose(league)
	var first := ""
	for item in league.screen.buttons:
		if str(item["id"]).begins_with("match:"):
			first = str(item["id"]).substr(6)
			break
	if first == "":
		first = str(extra["id"])
	league.screen.show_report(first)
	await _shot("report")
	screen_pose(league)
	league.screen.show_roundup(_reports(season, day))
	await _shot("roundup")
	screen_pose(league)
	league.screen.click("back")
	await _frames(2)
	league.screen.click("table")
	await _shot("table")
	screen_pose(league)
	league.screen.click("back")
	await _frames(2)
	print("EXIT day=", day, " mode=", league.screen.mode, " nav=", league.screen.nav.depth())
	quit()

## A played day with the most event rows, so the columns have something to say.
func _played_day(season: LeagueSeason) -> String:
	var best := ""
	var most := -1
	for date in season.record.fixtures.dates():
		var played := 0
		var events := 0
		for fx in season.record.fixtures.on(date):
			if str(fx["status"]) != "played":
				continue
			played += 1
			events += season.record.report.events(str(fx["id"])).size()
		if played >= 6 and events > most:
			most = events
			best = str(date)
	return best

func _reports(season: LeagueSeason, day: String) -> Array:
	var out: Array = []
	for fx in season.record.fixtures.on(day):
		if str(fx["status"]) == "played":
			out.append(season.report(str(fx["id"])))
	return out

## Print the BACK door the pose laid out: the evidence that the root disables it
## and a reading keeps it live.
func screen_pose(league: LeagueHost) -> void:
	var back := "absent"
	for item in league.screen.buttons:
		if str(item["id"]) != "back":
			continue
		back = "disabled" if bool(item.get("disabled", false)) else "enabled"
	print("POSE mode=", league.screen.mode, " back=", back, " nav=", league.screen.nav.depth())

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
	var file := "%s-%s" % [PREFIX, name]
	if img.get_width() < 1100:
		file += "-phone"
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % file))
	print("SHOT ", file, " ", img.get_size())
