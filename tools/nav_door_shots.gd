extends SceneTree

## Evidence capture for the phone's drawer door (#371).
##
## Boots the real game scene, opens a generated season and shoots the hub, the
## table and the calendar with the drawer door in its header lane, printing for
## each pose the home of the door, what answers a press on it, and how many body
## rows sit under it (must be none).
##
##   godot --path . --script res://tools/nav_door_shots.gd -- --design=913x411 --scale=2 --touch=1
##   godot --path . --script res://tools/nav_door_shots.gd -- --design=411x914 --scale=2 --touch=1

const SEED := 3710

var scene = null
var design := Vector2i(913, 411)
var scale := 2
var touch := true

func _initialize() -> void:
	_parse_args()
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = design * scale
	DisplayServer.window_set_size(design * scale)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Door Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT no season")
		quit()
		return
	season.advance()
	league.show_season(season)
	_pose(league)
	for pair in [["nav:fixtures", "hub"], ["nav:table", "table"], ["nav:calendar", "calendar"]]:
		league.screen.click(str(pair[0]))
		league.screen.panel.close()
		league.screen.panel.settle()
		league.screen.refresh()
		await _frames(2)
		_report(league.screen, str(pair[1]))
		await _shot("nav_door_%s_%s" % [str(pair[1]), str(design.x)])
	print("EXIT ok")
	quit()

func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--design="):
			var parts := raw.substr("--design=".length()).split("x")
			if parts.size() == 2:
				design = Vector2i(int(parts[0]), int(parts[1]))
		elif raw.begins_with("--scale="):
			scale = maxi(int(raw.substr("--scale=".length())), 1)
		elif raw.begins_with("--touch="):
			touch = int(raw.substr("--touch=".length())) != 0

func _pose(league: LeagueHost) -> void:
	var factor := float(scale)
	scene.chrome_scale = factor
	league.layer.transform = Transform2D.IDENTITY.scaled(Vector2(factor, factor))
	league.screen.ui_scale = factor
	league.screen.touch = touch
	league.screen.refresh()

func _report(screen, pose: String) -> void:
	var vp: Vector2 = screen.design_vp()
	var door: Rect2 = screen.panel.tab_rect(vp)
	var cont: Rect2 = LeagueExtra.primary_rect(vp, 140.0, screen.touch)
	var band := LeagueExtra.header_band(vp, UiChrome.fonts()["bold"], "Today's Fixtures",
		"", cont.size.x + 12.0, false, screen.touch)
	var crossing := 0
	for item in screen.body.button_rects():
		var r: Rect2 = item["rect"]
		if Rect2(r.position + screen.body.position, r.size).intersects(door.grow(-0.5)):
			crossing += 1
	print("POSE %s vp=%s door=%s press=%s rows_under=%d title=%s" % [pose, str(vp), str(door),
		screen.button_at(door.get_center()), crossing, str(band["title"])])

func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png("res://shots/%s.png" % name)
	print("WROTE res://shots/%s.png" % name)

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
