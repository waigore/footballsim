extends SceneTree

## Evidence capture for the System sheet (#109).
##
## Boots the real game scene, builds a generated season and plays three rounds so
## the date and table have a shape, then shoots:
##
##   * the hub with its `SYSTEM` door,
##   * the System sheet itself,
##   * Save As with its name field open,
##   * the load list opened from inside the season.
##
## Writes a PNG per pose into `res://shots/` and prints what it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/league_system_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("System Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.completed_matchdays() < 3 and guard < 10:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue109_hub_system_door")
	league.screen.click("system")
	await _shot("issue109_system")
	_print_doors(league, "system")
	league.screen.click("sys:save")
	await _shot("issue109_save_as")
	print("SAVE AS name=", league.screen.sys["name"])
	league.screen.click("sys:cancel")
	league.screen.click("sys:quick")
	await _shot("issue109_quick_saved")
	print("QUICK status=", league.screen.sys["status"])
	league.screen.click("sys:load")
	await _shot("issue109_load_from_season")
	print("LOAD mode=", league.screen.mode, " saves=", league.screen.saves.size())
	print("EXIT season=", season.save.slug)
	quit()

func _print_doors(league: LeagueHost, label: String) -> void:
	var ids: Array = []
	for item in league.screen.buttons:
		if str(item["id"]) != "":
			ids.append(str(item["id"]))
	print(label, " doors=", ", ".join(PackedStringArray(ids)))

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
