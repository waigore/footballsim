extends SceneTree

## Evidence capture for per-goal report highlights (#89).
##
## Boots the real game scene, builds a season, settles a matchday so its reports
## carry clips, then shoots the report (commentary + ▶), a clip mid-flight and a
## clip at the goal. Run it on a display — a headless run has no frame to read
## back.
##
##   godot --path . --script res://tools/goal_clip_shots.gd
##
## PNGs land in `res://shots/` (gitignored); copy the ones used as evidence into
## the wiki's `evidence/images/` tree.

const OUT := "res://shots"

var scene = null

func _initialize() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Clip Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	season.advance()
	league.show_season(season)
	var fixture := ""
	for fx in season.record.fixtures.all():
		if season.record.clips.list(str(fx["id"])).size() > 1:
			fixture = str(fx["id"])
			break
	if fixture == "":
		print("EXIT no fixture with clips")
		quit()
		return
	league.screen.show_report(fixture)
	var rows := season.record.clips.list(fixture)
	print("REPORT fixture=", fixture, " goals=", rows.size(), " mode=", league.screen.mode)
	for row in rows:
		print("  goal ", row["goal_index"], " ", row["minute"], "' ", row["scorer_name"],
			" · ", row["commentary"])
	await _shot("report_goals")
	var door := ""
	for item in league.screen.buttons:
		if str(item["id"]).begins_with("goal:"):
			door = str(item["id"])
			break
	if door == "":
		print("EXIT the report offers no play door")
		quit()
		return
	league.screen.click(door)
	print("CLIP started door=", door, " replay=", scene.replay != null,
		" home=", scene.home_id, " away=", scene.away_id)
	await _frames(60)
	await _shot("goal_clip_play")
	# Wait on the state, not a frame count: the shot has to be in the net.
	# Wait on the state, not a frame count: the clip has to reach its shot. A
	# windowed run has no vsync cap, so pace it by the clock and a wall deadline.
	var deadline := Time.get_ticks_msec() + 25000
	while scene.replay != null and int(scene.engine.score[0]) + int(scene.engine.score[1]) == 0 \
			and Time.get_ticks_msec() < deadline:
		await process_frame
	print("CLIP clock=", scene.engine.display_clock(), " score=", scene.engine.score)
	await _shot("goal_clip_goal")
	scene._skip()
	await _frames(6)
	print("DONE back to report mode=", league.screen.mode, " layer=", league.layer.visible)
	quit()

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame

func _shot(name: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var path := "%s/%s.png" % [OUT, name]
	img.save_png(ProjectSettings.globalize_path(path))
	print("SHOT ", path, " ", img.get_width(), "x", img.get_height())
