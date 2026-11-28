extends SceneTree

## Evidence capture for the table's form reading (DR-20261128-12).
##
## Boots the real game scene, builds a generated season, plays six matchdays so
## every club has a form, opens the TABLE sheet and presses its `FORM` door,
## then shoots the desktop sheet and the phone-landscape pose. Prints the column
## geometry, the pip lane and the scroll the reading needs beside the pixels.
##
##   godot --path . --resolution 1600x900 --script res://tools/league_form_shots.gd

const SEED := 1112

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Form Reading Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("SKIP no season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 6 and guard < 16:
		season.advance()
		guard += 1
	league.show_season(season)
	await _frames(3)
	league.screen.click("table")
	await _frames(2)
	league.screen.click("tbl:mode:form")
	await _frames(3)
	_report("desktop_1280", league)
	await _shot("league_form_1600")
	await _width(league, 730.7)
	_report("compact_730", league)
	await _shot("league_form_730")
	await _width(league, 411.0)
	_report("phone_411", league)
	league.close()
	await _frames(2)
	print("EXIT")
	quit()


func _width(league: LeagueHost, design_width: float) -> void:
	var scale := maxf(league.screen.size.x / design_width, 1.0)
	scene.hud_scale = scale
	league.sync(Transform2D.IDENTITY.scaled(Vector2(scale, scale)), scale, false)
	league.screen.refresh()
	await _frames(3)


func _report(name: String, league: LeagueHost) -> void:
	var screen: LeagueScreen = league.screen
	var vp: Vector2 = screen.design_vp()
	var heads: Array = []
	var lanes: Array = []
	var rows := 0
	var names: Array = []
	for item in screen.buttons:
		var kind := str(item.get("kind", ""))
		if kind == "head":
			heads.append("%s@%.0f" % [str(item["label"]), (item["rect"] as Rect2).position.x])
		elif kind == "table_row":
			rows += 1
			if lanes.is_empty():
				var places: Dictionary = item["places"]
				for col in places["cols"]:
					lanes.append("%s=%s" % [str(col["label"]), Rect2(float(col["right"]) - float(col["w"]), 0.0, float(col["w"]), 0.0)])
			if names.size() < 3:
				names.append("%s %s" % [str((item["row"] as Dictionary).get("club_abbr", "")),
					LeagueFormGuide.label(item.get("form", []))])
	print("FORM %s vp=%s mode=%s rows=%d heads=%s lanes=%s hscroll=%.0f of %.0f" % [
		name, str(vp), screen.book.table.mode, rows, str(heads), str(lanes),
		screen.body.hscroll, screen.body.max_hscroll()])
	print("FORM marks ", str(names))


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await _frames(4)
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
	print("SHOT shots/%s.png %s" % [name, str(img.get_size())])
