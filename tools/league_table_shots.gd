extends SceneTree

## Evidence capture for the league table's full reading (#72/#73/#74).
##
## Boots the real game scene, builds a generated season, plays eight rounds so
## the table has a shape, then shoots:
##
##   * the full table on a desktop sheet (every overall, home and away column),
##   * the same table sorted by goals scored (official places unchanged),
##   * the compact reading after the mode door,
##   * the full table in the phone-landscape design space (every column inside
##     the row) and the phone portrait before/after a sideways drag.
##
## Writes a PNG per pose into `res://shots/` and prints the geometry it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/league_table_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Table Evidence", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue72_hub")
	# The desktop sheet opens on the full reading.
	league.screen.click("table")
	await _shot("issue72_full_desktop")
	_print_table(league, "desktop full")
	var sorted_head := _head(league.screen, "tbl:sort:gf")
	if sorted_head.size() > 0:
		league.screen.click("tbl:sort:gf")
		await _shot("issue72_full_sorted_by_gf")
		_print_table(league, "desktop full sorted by GF")
		league.screen.click("tbl:sort:gf")
	# Compact reading on the same sheet.
	league.screen.click("tbl:mode:compact")
	await _shot("issue72_compact_desktop")
	print("COMPACT heads=", _heads(league.screen))
	league.screen.click("tbl:mode:full")
	# Phone landscape: the overlay scale shrinks the design space, every column
	# still has to sit inside the row.
	await _width(league, 873.0)
	await _shot("issue73_phone_landscape_full")
	_print_geometry(league, "phone landscape")
	# Phone portrait: the full table is wider than the window; one sideways drag
	# reaches the home and away columns.
	DisplayServer.window_set_size(Vector2i(900, 1600))
	await _frames(6)
	await _width(league, 450.0)
	await _shot("issue73_phone_portrait_left")
	_print_geometry(league, "phone portrait")
	_drag(league, Vector2(400.0, 300.0), Vector2(120.0, 300.0))
	await _shot("issue73_phone_portrait_panned")
	print("HSCROLL ", league.screen.body.hscroll, " of ", league.screen.body.max_hscroll())
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

## The table pose's numbers: what a player can see without swiping.
func _print_geometry(league: LeagueHost, label: String) -> void:
	var screen: LeagueScreen = league.screen
	var view = screen.book.table
	var widest := 0.0
	for item in screen.buttons:
		if str(item["kind"]) == "table_row":
			widest = maxf(widest, (item["rect"] as Rect2).end.x)
	print("%s: mode=%s row_right=%.0f window=%.0f hscroll=%.0f of %.0f" % [
		label, view.mode, widest, screen.design_vp().x, screen.body.hscroll,
		screen.body.max_hscroll()])
	print("  heads=", _heads(screen))

func _heads(screen: LeagueScreen) -> int:
	var out := 0
	for item in screen.buttons:
		if str(item["kind"]) == "head":
			out += 1
	return out

func _head(screen: LeagueScreen, id: String) -> Dictionary:
	for item in screen.buttons:
		if str(item["id"]) == id:
			return item
	return {}

func _print_table(league: LeagueHost, label: String) -> void:
	var screen: LeagueScreen = league.screen
	print("TABLE ", label, " mode=", screen.book.table.mode, " sort=", screen.book.table.sort,
		" dir=", screen.book.table.dir)
	var lines: Array = []
	for item in screen.buttons:
		if str(item["kind"]) != "table_row":
			continue
		var row: Dictionary = item["row"]
		lines.append("#%d %s P%d GF%d GA%d GD%+d H%d/%d/%d A%d/%d/%d pts%d" % [
			int(row["position"]), str(row["club_abbr"]), int(row["played"]), int(row["gf"]),
			int(row["ga"]), int(row["gf"]) - int(row["ga"]), int(row["home_won"]),
			int(row["home_drawn"]), int(row["home_lost"]), int(row["away_won"]),
			int(row["away_drawn"]), int(row["away_lost"]), int(row["points"])])
	for i in range(mini(lines.size(), 6)):
		print("  ", lines[i])

## A finger drag through the same handler the game uses.
func _drag(league: LeagueHost, from: Vector2, to: Vector2, steps: int = 8) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	league.handle_input(down, from)
	var p := from
	for i in range(1, steps + 1):
		p = from.lerp(to, float(i) / float(steps))
		var motion := InputEventMouseMotion.new()
		motion.position = p
		league.handle_input(motion, p)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	league.handle_input(up, p)

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
