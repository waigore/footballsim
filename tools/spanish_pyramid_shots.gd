extends SceneTree

var scene = null

func _initialize() -> void:
	PLDatabase.cache_dir = "user://shots_spain_cache_%d" % OS.get_process_id()
	LeagueSave.dir = "user://shots_spain_saves_%d" % OS.get_process_id()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	league.open_wizard()
	await _frames(2)
	league.screen.click("wleague:LL2")
	await _shot("issue499_wizard")
	print("WIZARD competitions=%s" % str(league.screen.wizard.get("competitions", [])))
	var season := LeagueSeason.create("Spain Evidence", "generated", "fixture_days", 4960, ["LL", "LL2"])
	if season == null:
		print("EXIT could not create the Spanish season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 6 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue499_hub")
	print("HUB competitions=%s" % str(season.save.competition_ids()))
	league.screen.click("table")
	await _frames(2)
	league.screen.click("tbl:league:LL2")
	await _shot("issue499_table_ll2")
	var rules := season.save.rules_for("LL2")
	print("TABLE tab=%s bands=%s labels=%s" % [
		str(league.screen.book.table.league_tab),
		str(LeagueTableChrome.bands_for(rules)),
		str(LeagueTableChrome.labels_for(LeagueTableChrome.bands_for(rules), true))])
	var filial := ""
	for row in season.record.standings.table("LL2"):
		if bool((row as Dictionary).get("filial", false)):
			filial = "%s at %d" % [str((row as Dictionary)["club_name"]),
				int((row as Dictionary)["position"])]
			break
	print("FILIAL %s" % filial)
	scene.menus.close()
	await _frames(2)
	scene.wiki_host.open_page_over_league(WikiModel.LEAGUE, "LL2")
	await _shot("issue499_encyclopedia")
	var page := WikiModel.page(WikiModel.LEAGUE, "LL2")
	print("ENCYCLOPEDIA title=%s subtitle=%s chips=%d" % [str(page.get("title", "")),
		str(page.get("subtitle", "")), _chips(page)])
	scene.menus.close()
	await _frames(2)
	_finish(season)
	league.show_season(season, true)
	await _shot("issue499_podium")
	var summary := season.summary()
	var sections: Array = summary.get("competitions", [])
	var lower: Dictionary = (sections[1] as Dictionary) if sections.size() > 1 else {}
	print("PODIUM sections=%d lower=%s ladder=%d/%d bracket=%s" % [
		sections.size(), str(lower.get("id", "")),
		((lower.get("promotion", {}) as Dictionary).get("automatic", []) as Array).size(),
		((lower.get("promotion", {}) as Dictionary).get("playoff", []) as Array).size(),
		str(((summary.get("playoffs", {}) as Dictionary).get("LL2", {}) as Dictionary).get("text", ""))])
	season.close()
	print("EXIT done")
	quit()

func _finish(season: LeagueSeason) -> void:
	var places := {}
	for cid in season.save.actives:
		var table: Array = season.record.standings.table(str(cid))
		for i in range(table.size()):
			places[str((table[i] as Dictionary)["club_id"])] = i
	for row in PLDatabase.rows("SELECT id, home_club_id, away_club_id FROM league_fixture;"):
		var home_place: int = places.get(str(row["home_club_id"]), 99)
		var away_place: int = places.get(str(row["away_club_id"]), 99)
		var hg := 2 if home_place < away_place else 0
		var ag := 2 if away_place < home_place else 0
		PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = ?, "
			+ "away_goals = ? WHERE id = ?;", [hg, ag, str(row["id"])])
	season.record.standings.recompute()
	season.save.set_status("complete")

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
	RenderingServer.force_draw(false)
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT ", name, " ", img.get_size(), " ", hash(img.get_data()))
