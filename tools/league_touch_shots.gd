extends SceneTree

## Evidence capture for the league's touch targets (#204).
##
## Boots the real game scene, builds a generated season, then presents the table
## as a handset would see it — the touch pose on and a 913x411 design space — and
## shoots:
##
##   * the compact table with finger-sized rows and sortable headers,
##   * the same table after a header press, so the sorted rule is visible in a
##     48-unit band,
##   * the closed drawer door, which is now a labelled square inboard of the
##     gesture strip,
##   * the panel that door opens.
##
## With `--touch=0` it shoots the desktop reading instead: the same season, no
## touch pose, so the frame shows the dense pitch the desktop keeps.
##
## It also prints the geometry it shot, so the numbers are checkable without the
## pictures. Run it on a display; a headless run has no frame to read back.
##
## The window is sized to the design space times the scale, with the stretch mode
## switched off, **before** the scene boots: a plain `--resolution` is mapped onto
## the project's base viewport, so a "phone" capture came out at 999.5x450 design
## units instead of the handset's 913x411. The chrome layer is then set to that
## same factor, so one design unit is exactly `scale` device pixels — without it
## the window says 913x411 while the shell keeps drawing at its own 1.25 density.
##
##   xvfb-run -a godot --path . --script res://tools/league_touch_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1
##   xvfb-run -a godot --path . --script res://tools/league_touch_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0

const SEED := 2041
## The handset the targets are sized for, in design units.
const DESIGN := Vector2i(913, 411)
## Device pixels per design unit: 2x keeps the 48-unit rows' type readable.
const SCALE := 2

var scene = null
var design: Vector2i = DESIGN
var scale: int = SCALE
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
	var season := LeagueSeason.create("Touch Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 6 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	_pose(league)
	league.screen.click("nav:table")
	league.screen.refresh()
	await _frames(2)
	_report(league.screen, "table")
	await _shot("league_touch_table" if touch else "league_table_desktop")
	if not touch:
		print("EXIT ok")
		quit()
		return

	league.screen.click("tbl:mode:full")
	league.screen.refresh()
	await _frames(2)
	await _shot("league_touch_table_full")

	league.screen.click("tbl:sort:points")
	league.screen.refresh()
	await _frames(2)
	await _shot("league_touch_table_sorted")

	league.screen.panel.close()
	league.screen.panel.settle()
	league.screen.refresh()
	await _frames(2)
	await _shot("league_touch_drawer")

	league.screen.click("panel")
	league.screen.panel.settle()
	league.screen.refresh()
	await _frames(2)
	await _shot("league_touch_panel")
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

## One coherent reading: the chrome layer, the sheet and the window all carry the
## same factor, so one design unit is exactly `scale` device pixels. The shell
## computes its own density from the display, which would leave a "913x411 at 2x"
## frame drawn at 1.25 pixels per unit — the pose would name one space and the
## picture another.
func _pose(league: LeagueHost) -> void:
	var factor := float(scale)
	scene.chrome_scale = factor
	league.layer.transform = Transform2D.IDENTITY.scaled(Vector2(factor, factor))
	league.screen.ui_scale = factor
	league.screen.touch = touch
	league.screen.refresh()

## Print what the pose actually laid, so the shot and the numbers agree.
func _report(screen, pose: String) -> void:
	var vp: Vector2 = screen.design_vp()
	var view: Dictionary = LeagueView.build(screen)
	var items: Array = LeagueTableView.new().layout(vp, view)
	var row_h := 0.0
	var head_h := 0.0
	var rows := 0
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "table_row":
			rows += 1
			row_h = maxf(row_h, rect.size.y)
		elif str(item["kind"]) == "head" and str(item["id"]) != "":
			head_h = maxf(head_h, rect.size.y)
	print("SHOT %s vp=%s touch=%s rows=%d row_h=%.1f head_h=%.1f door=%s" % [
		pose, vp, str(screen.touch), rows, row_h, head_h, str(screen.panel.tab_rect(vp))])

func _shot(name: String) -> void:
	await _frames(2)
	var img := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png("res://shots/%s.png" % name)
	print("WROTE res://shots/%s.png %dx%d" % [name, img.get_width(), img.get_height()])

func _frames(n: int) -> void:
	for i in range(n):
		await process_frame
