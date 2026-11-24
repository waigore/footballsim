extends SceneTree

## Evidence capture for issue #80: a league club row opens the club's team page.
##
## Boots the real game scene, builds a generated season, presses a club row on
## the hub's table column and again on the full TABLE pose, then walks BACK and
## `✕` to prove the season comes back where it was. Writes a PNG per pose into
## `res://shots/`. Run it on a display; a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/league_club_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Club Row Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue80_hub")
	# The hub's wide table column: press the club row straight off the hub.
	var hub_row := _row(league.screen)
	print("HUB row ", hub_row)
	league.screen.click(hub_row)
	await _shot("issue80_hub_row_team_page")
	print("OPEN page=", str(scene.wiki_host.screen.current()), " league_open=", league.is_open())
	scene.wiki_host.screen.click("back")
	await _shot("issue80_hub_back")
	print("BACK league_open=", league.is_open(), " mode=", league.screen.mode)
	# The full table: a row there opens the same page and BACK returns to it.
	league.screen.click("table")
	await _shot("issue80_table")
	var table_row := _row(league.screen)
	print("TABLE row ", table_row)
	league.screen.click(table_row)
	await _shot("issue80_table_row_team_page")
	print("OPEN page=", str(scene.wiki_host.screen.current()))
	scene.wiki_host.screen.click("back")
	await _shot("issue80_table_back")
	print("BACK mode=", league.screen.mode)
	# A player from the squad keeps the crumb trail inside the encyclopedia.
	scene.wiki_host.open_page_over_league(WikiModel.TEAM, table_row.substr(5))
	await _shot("issue80_team_page_squad")
	scene.wiki_host.screen.click("close")
	await _shot("issue80_close_back_to_table")
	print("CLOSE mode=", league.screen.mode, " league_open=", league.is_open())
	print("EXIT season=", season.save.slug)
	quit()

## The first club row on the pose that is showing.
func _row(screen: LeagueScreen) -> String:
	for item in screen.buttons:
		if str(item["kind"]) == "table_row":
			return str(item["id"])
	return ""

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
