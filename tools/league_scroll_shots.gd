extends SceneTree

## Evidence capture for the league scroll fix (issue #69).
##
## Boots the real game scene in the handheld design space (`--ui-scale=2.2`),
## builds a generated season, then shoots the table and the hub at the top of
## their scroll and again after a finger drag. Run it on a display (or under
## `xvfb-run`); a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/league_scroll_shots.gd -- --ui-scale=2.2

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Scroll Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	print("VP ", league.screen.design_vp(), " SCALE ", league.screen.ui_scale)
	await _shot("issue69_hub_top")
	_drag(league, Vector2(400.0, 330.0), Vector2(400.0, 130.0))
	await _shot("issue69_hub_scrolled")
	print("HUB scroll ", league.screen.body.scroll, " of ", league.screen.body.max_scroll())
	league.screen.click("table")
	await _shot("issue69_table_top")
	print("TABLE scroll ", league.screen.body.scroll, " of ", league.screen.body.max_scroll())
	_drag(league, Vector2(400.0, 330.0), Vector2(400.0, 120.0))
	await _shot("issue69_table_scrolled")
	print("TABLE scroll ", league.screen.body.scroll, " of ", league.screen.body.max_scroll())
	league.screen.key(KEY_END)
	await _shot("issue69_table_end")
	print("TABLE end ", league.screen.body.scroll, " of ", league.screen.body.max_scroll())
	print("EXIT season=", season.save.slug)
	quit()

## A finger drag through the same handler the game uses.
func _drag(league: LeagueHost, from: Vector2, to: Vector2, steps: int = 6) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	league.handle_input(down, from)
	var p := from
	for i in range(1, steps + 1):
		p = from.lerp(to, float(i) / float(steps))
		var motion := InputEventMouseMotion.new()
		motion.position = p
		league.handle_input(motion, p)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	league.handle_input(up, p)

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
