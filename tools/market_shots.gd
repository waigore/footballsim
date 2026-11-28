extends SceneTree

## Evidence capture for the season rollover (#440): the finished season's podium
## with NEW SEASON, and the hub that door opens on season two.
##
## The window is sized to the design space times the scale, with the stretch mode
## switched off before the scene boots — a plain `--resolution` is mapped onto the
## project's base viewport. Run on a display; a headless run has no frame.
##
##   xvfb-run -a godot --path . --script res://tools/market_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0
##   xvfb-run -a godot --path . --script res://tools/market_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1

const SEED := 4401

var scene = null
var design := Vector2i(1600, 900)
var scale := 1
var touch := false
var tag := "desktop"


func _initialize() -> void:
	_parse_args()
	tag = "phone" if touch else "desktop"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = design * scale
	DisplayServer.window_set_size(design * scale)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Rollover Evidence", "generated", "fixture_days", SEED,
		["PL"], true)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	_finish(season)
	league.show_season(season, true)
	_pose(league)
	await _shot("season_rollover_podium_%s" % tag)
	var before := "%s %s" % [season.save.season_label(), season.save.current_date()]
	league.screen.click("season:new")
	_pose(league)
	await _frames(8)
	await _shot("season_rollover_hub_%s" % tag)
	print("EXIT ", tag, " from=", before, " label=", season.save.season_label(),
		" index=", season.save.season_index(), " date=", season.save.current_date(),
		" unplayed=", season.record.fixtures.unplayed())
	var slug := season.save.slug
	season.close()
	LeagueSaveCatalog.remove(slug)
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


func _finish(season: LeagueSeason) -> void:
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		var hg := 3 if home < away else 1
		var ag := 1 if home < away else 3
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [hg, ag, str(row["id"])])
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	SeasonSettle.apply(season)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("WROTE res://shots/%s.png %dx%d" % [name, img.get_width(), img.get_height()])
