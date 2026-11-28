extends SceneTree

## Evidence capture for the cups destination (#459, DR-20261128-22): the panel
## with its CUPS row, the cup hub, a cup page with its round rail, and the
## podium's domestic honours. Boots the real scene on a generated season, plays
## to the winter break so the FA Cup has rounds behind it, then walks the poses.
##
##   godot --path . --resolution 1600x900 --script res://tools/cups_shots.gd

const SEED := 4590

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Cups Evidence", "generated", "fixture_days", SEED,
		["PL"], true, ["England"])
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.save.current_date() < "2026-12-20" and guard < 400:
		var result: Dictionary = season.advance()
		if not (result.get("pending", []) as Array).is_empty():
			season.set_watch(str((result["pending"] as Array)[0]["id"]), false)
			season.cancel_watch()
		guard += 1
	league.show_season(season)
	await _shot("cups_hub_panel_closed")
	league.screen.panel.open()
	league.screen.panel.settle()
	league.screen.refresh()
	await _shot("cups_panel")
	league.screen.click("nav:cups")
	league.screen.panel.settle()
	await _shot("cups_hub")
	league.screen.click("cup:FAC")
	await _shot("cups_cup_page")
	league.screen.click("round:R3")
	await _shot("cups_round_rail")
	league.screen.click("cup:CS")
	await _shot("cups_supercup")
	var cups: Array = LeagueCupHub.competitions(season)
	print("EXIT cups=", cups.size(), " winners=", _winners(cups))
	quit()


func _winners(cups: Array) -> Array:
	var out: Array = []
	for cup in cups:
		if str(cup.get("winner", "")) != "":
			out.append(str(cup["id"]))
	return out

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
	print("SHOT ", name)
