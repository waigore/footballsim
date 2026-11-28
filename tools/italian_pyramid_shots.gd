extends SceneTree

var scene = null

func _initialize() -> void:
	PLDatabase.cache_dir = "user://shots_italy_cache_%d" % OS.get_process_id()
	LeagueSave.dir = "user://shots_italy_saves_%d" % OS.get_process_id()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Italy Evidence", "generated", "fixture_days", 420, ["SA", "SB"])
	if season == null:
		print("EXIT could not create the Italian season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 6 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue420_hub")
	print("HUB competitions=%s" % str(season.save.competition_ids()))
	league.screen.click("table")
	await _frames(2)
	league.screen.click("tbl:league:SB")
	await _shot("issue420_table_serie_b")
	print("TABLE tab=%s bands=%s labels=%s" % [
		str(league.screen.book.table.league_tab),
		str(LeagueTableChrome.bands_for(season.save.rules_for("SB"))),
		str(LeagueTableChrome.labels_for(
			LeagueTableChrome.bands_for(season.save.rules_for("SB")), true))])
	scene.menus.close()
	await _frames(2)
	scene.wiki_host.open_page_over_league(WikiModel.LEAGUE, "SA")
	await _shot("issue420_encyclopedia_serie_a")
	var page := WikiModel.page(WikiModel.LEAGUE, "SA")
	print("ENCYCLOPEDIA title=%s chips=%d" % [str(page.get("title", "")), _chips(page)])
	season.close()
	print("EXIT done")
	quit()

func _chips(page: Dictionary) -> int:
	for block in page.get("blocks", []):
		if str((block as Dictionary).get("k", "")) == "chips":
			return (block["items"] as Array).size()
	return 0

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
