extends SceneTree

## Evidence capture for the club page's finances block (#442): cash, the wage
## bill against its budget, FFP headroom and the ledger tail, at the desktop
## design space and at a handset pose.
##
##   xvfb-run -a godot --path . --script res://tools/finance_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0
##   xvfb-run -a godot --path . --script res://tools/finance_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1

const SEED := 4421

var scene = null
var design := Vector2i(1600, 900)
var scale := 1
var touch := false
var tag := "desktop"


func _initialize() -> void:
	_parse_args()
	tag = "phone" if touch else "desktop"
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = design * scale
	DisplayServer.window_set_size(design * scale)
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var season := LeagueSeason.create("Finance Evidence", "generated", "fixture_days", SEED,
		["PL"], false)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY name LIMIT 1;").get("id", ""))
	MarketFinance.month(season.save.current_date())
	MarketFinance.post_amortisation(club_id, season.save.current_date(), 40000000, 4, "")
	scene.menus.close()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.TEAM, club_id)
	await _frames(5)
	var screen = scene.wiki_host.screen
	if screen != null and screen.body != null:
		screen.body.scroll_to(0.0)
		for row in screen.body.rows():
			if str(row.get("k", "")) != "section" or str(row.get("text", "")) != "FINANCES":
				continue
			var rect: Rect2 = row.get("rect", Rect2())
			screen.body.scroll_to(maxf(rect.position.y - 120.0, 0.0))
			break
		await _frames(3)
	await _shot("market_finances_%s" % tag)
	print("EXIT ", tag, " club=", club_id, " cash=", MarketFinance.cash(club_id),
		" wage=", MarketFinance.annual_wages(club_id),
		" budget=", MarketFinance.wage_budget(club_id),
		" ffp=", MarketFinance.ffp_headroom(club_id))
	var slug := season.save.slug
	season.close()
	LeagueSaveCatalog.remove(slug)
	quit()


func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--design="):
			var parts := raw.substr(9).split("x")
			design = Vector2i(int(parts[0]), int(parts[1]))
		elif raw.begins_with("--scale="):
			scale = int(raw.substr(8))
		elif raw == "--touch=1":
			touch = true


func _shot(name: String) -> void:
	await _frames(3)
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT ", name)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
