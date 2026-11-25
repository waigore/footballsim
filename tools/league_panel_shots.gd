extends SceneTree

## Evidence capture for Teams of Interest, the left panel and System (#103).
##
## Boots the real game scene, builds a generated season with eight rounds played,
## then walks the panel, the interest list and its search, a long-press context
## menu, Stats and System, writing a PNG per pose into `res://shots/`. Run on a
## display — a headless run has no frame to read back.
##
##   godot --path . --script res://tools/league_panel_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Panel Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("league_panel_closed")
	league.screen.panel.open()
	league.screen.panel.settle()
	league.screen.refresh()
	await _shot("league_panel")
	league.screen.click("nav:interest")
	league.screen.panel.settle()
	await _shot("league_interest")
	for code in [KEY_A, KEY_R, KEY_S]:
		league.screen.key(code)
	await _shot("league_interest_search")
	league.screen.click("interest:add:ARS")
	league.screen.click("interest:add:LIV")
	await _shot("league_interest_marked")
	league.screen.click("back")
	league.screen.panel.settle()
	var plan: Array = season.plan()
	var home := str(plan[0]["home_club_id"])
	season.interest.set_interest(home, true)
	league.screen.refresh()
	await _shot("league_hub_marked")
	var row := Rect2()
	for item in league.screen.buttons:
		if str(item["id"]) == "fixture:" + str(plan[0]["id"]):
			row = item["rect"]
	league.screen.open_interest_at(Vector2(row.position.x + 80.0, row.position.y + 13.0))
	await _shot("league_interest_menu")
	league.screen.click("interest:close")
	league.screen.click("nav:stats")
	league.screen.panel.settle()
	await _shot("league_stats")
	league.screen.click("nav:system")
	league.screen.panel.settle()
	await _shot("league_system")
	league.screen.click("system:save")
	await _shot("league_save")
	print("EXIT interest=", season.interest.all(), " slug=", season.save.slug)
	quit()

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
