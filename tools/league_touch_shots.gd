extends SceneTree

## Evidence capture for the league's touch targets (#204).
##
## Boots the real game scene, builds a generated season, then presents the table
## as a phone would see it — the touch pose on and a 913x411 landscape design
## space — and shoots:
##
##   * the compact table with finger-sized rows and sortable headers,
##   * the same table after a header press, so the sorted rule is visible in a
##     48-unit band,
##   * the closed drawer door, which is now a labelled square inboard of the
##     gesture strip,
##   * the panel that door opens.
##
## It also prints the geometry it shot, so the numbers are checkable without the
## pictures. Run it on a display; a headless run has no frame to read back.
##
## Run it at double the phone's design space so the 2x pixels show the type:
##
##   godot --path . --resolution 1826x822 --script res://tools/league_touch_shots.gd

const SEED := 2041

var scene = null

func _initialize() -> void:
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
	# The handheld pose: this is the device the targets are sized for.
	league.screen.touch = true
	# Two device pixels per design unit: the design space stays the phone's
	# 913x411, and the shot is large enough to read the rows it is proving.
	league.screen.ui_scale = 2.0
	league.screen.refresh()
	league.screen.click("nav:table")
	league.screen.refresh()
	await _frames(2)
	_report(league.screen, "compact")
	await _shot("league_touch_table")

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
