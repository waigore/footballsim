extends SceneTree

## Evidence capture for the compact league table (#102).
##
## Boots the real game scene, builds a generated season, plays six rounds so the
## record has numbers in it, then shoots:
##
##   * the wide hub with its side table carrying the whole overall record,
##   * the TABLE sheet's compact reading on a desktop window,
##   * the same reading at the phone-landscape design space, where all ten
##     columns still have to fit inside the row,
##   * the compact reading sorted by goals scored (the new columns sort).
##
## Writes a PNG per pose into `res://shots/` and prints the geometry it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/league_compact_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Compact Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.completed_matchdays() < 6 and guard < 16:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue102_hub_wide")
	_print_hub(league)
	# The desktop sheet opens on the full reading; the compact door switches it.
	league.screen.click("table")
	league.screen.click("tbl:mode:compact")
	await _shot("issue102_compact_desktop")
	_print_geometry(league, "desktop compact")
	# Phone landscape: the overlay scale shrinks the design space to 411 units
	# tall, which is where the compact reading is the default.
	await _width(league, 873.0)
	await _shot("issue102_compact_phone_landscape")
	_print_geometry(league, "phone landscape compact")
	# Back to a desktop sheet: a new Compact column is sortable like any other.
	await _width(league, 1280.0)
	league.screen.click("tbl:sort:gf")
	await _shot("issue102_compact_sorted_by_gf")
	print("SORTED heads=", _heads(league.screen), " sort=", league.screen.book.table.sort)
	print("EXIT season=", season.save.slug)
	quit()

## Give the league surface a design width by scaling the whole layer, then lay
## the sheet out again for that space.
func _width(league: LeagueHost, design_width: float) -> void:
	var scale := maxf(league.screen.size.x / design_width, 1.0)
	scene.hud_scale = scale
	league.sync(Transform2D.IDENTITY.scaled(Vector2(scale, scale)), scale, false)
	league.screen.refresh()
	await _frames(3)
	print("DESIGN VP ", league.screen.design_vp(), " window ", league.screen.size, " scale ", scale)

func _print_geometry(league: LeagueHost, label: String) -> void:
	var screen: LeagueScreen = league.screen
	var view = screen.book.table
	var widest := 0.0
	for item in screen.buttons:
		if str(item["kind"]) == "table_row":
			widest = maxf(widest, (item["rect"] as Rect2).end.x)
	print("%s: mode=%s heads=%d row_right=%.0f window=%.0f hscroll=%.0f of %.0f" % [
		label, view.mode, _heads(screen), widest, screen.design_vp().x,
		screen.body.hscroll, screen.body.max_hscroll()])

## The hub side table's own row paint: the columns a player sees there.
func _print_hub(league: LeagueHost) -> void:
	var seen := 0
	for item in league.screen.buttons:
		if str(item["kind"]) == "table_row":
			var places: Dictionary = item["places"]
			if seen == 0:
				var keys: Array = []
				for col in places["cols"]:
					keys.append(str(col["label"]))
				print("HUB columns=", keys, " club_x=", places["club_x"],
					" club_w=", places["club_w"])
			seen += 1
	print("HUB table rows=", seen)

func _heads(screen: LeagueScreen) -> int:
	var out := 0
	for item in screen.buttons:
		if str(item["kind"]) == "head":
			out += 1
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
	print("SHOT ", name, " ", img.get_size())
