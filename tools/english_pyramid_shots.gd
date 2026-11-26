extends SceneTree

## Evidence capture for the English pyramid (#258/#259/#260/#261): the New
## League sheet's country groups on a desktop and on a phone, a Championship
## table with its own legend, and a five-tier podium carrying the play-offs.
##
##   godot --path . --script res://tools/english_pyramid_shots.gd
##
## The season it creates lives in `user://saves` like any other save; the PNGs
## land in `res://shots/`. It builds the finished season by writing results
## straight to the ledger (the clock would play 2 588 fixtures) and settles the
## play-offs through the real summary.

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	league.open_wizard()
	await _shot("issue261_wizard_desktop")
	scene.dev.ui_scale = maxf(1.0, scene.get_viewport().get_visible_rect().size.y / 620.0)
	scene._sync_overlay_scale()
	league.screen.ui_scale = scene.dev.ui_scale
	league.screen.refresh()
	await _shot("issue261_wizard_phone")
	league.close()
	scene.dev.ui_scale = 1.0
	scene._sync_overlay_scale()
	var season := _finished("Pyramid Evidence", 7301,
		["PL", "CH", "L1", "L2", "NL"])
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	league.screen.mode = LeagueScreen.MODE_TABLE
	league.screen.book.table.league_tab = "CH"
	league.screen.refresh()
	await _shot("issue260_table_championship")
	league.screen.mode = LeagueScreen.MODE_PODIUM
	league.screen.refresh()
	await _shot("issue260_podium")
	var summary := season.summary()
	print("EXIT season=", season.save.slug,
		" brackets=", (summary.get("playoffs", {}) as Dictionary).size(),
		" swaps=", ((summary.get("pyramid", {}) as Dictionary).get("links", []) as Array).size())
	quit()

func _finished(name: String, seed: int, comps: Array) -> LeagueSeason:
	var built := LeagueSeason.create(name, "generated", "fixture_days", seed, comps)
	if built == null:
		return null
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home := str(row["home_club_id"])
		var away := str(row["away_club_id"])
		PLDatabase.execute(
			"UPDATE league_fixture SET status = 'played', home_goals = ?, away_goals = ? "
			+ "WHERE id = ?;", [2 if home < away else 0, 2 if away < home else 0, str(row["id"])])
	built.record.standings.recompute()
	if built.record.fixtures.unplayed() == 0:
		built.save.set_status("complete")
	return built

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(3)
	RenderingServer.force_draw(false)
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
	print("SHOT %s %s %dx%d" % [name, str(hash(img.get_data())), img.get_width(), img.get_height()])
