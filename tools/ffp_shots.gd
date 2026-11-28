extends SceneTree

## Evidence capture for the club page's FFP headroom after #449: the FINANCES
## block's rolling three-year headroom, at the desktop design space and a pose.
##
##   godot --path . --script res://tools/ffp_shots.gd -- --design=1600x900 --scale=1 --touch=0
##   godot --path . --script res://tools/ffp_shots.gd -- --design=913x411 --scale=2 --touch=1

const SEED := 4491

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
	var season := LeagueSeason.create("FFP Evidence", "generated", "fixture_days", SEED,
		["PL"], false)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	for i in range(3):
		var date := FixtureCalendar.add_years(season.save.current_date(), i)
		MarketFinance.post(club_id, date, MarketFinance.KIND_COMMERCIAL,
			MarketFinance.revenue_base(club_id), "commercial")
		MarketFinance.post(club_id, date, MarketFinance.KIND_WAGE,
			-MarketFinance.annual_wages(club_id), "squad")
		MarketFinance.post_amortisation(club_id, date, 40000000, 4, "")
	PLRepository.shared().invalidate()
	scene.menus.close()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.TEAM, club_id)
	await _frames(5)
	_scroll_to("FINANCES", 120.0)
	await _frames(3)
	await _shot("market_ffp_%s" % tag)
	var measured := MarketFFP.measure(club_id)
	print("EXIT ", tag, " club=", club_id, " headroom=", MarketFFP.headroom(club_id),
		" sheet=", MarketFinance.ffp_headroom(club_id), " measure=", JSON.stringify(measured))
	var slug := season.save.slug
	season.close()
	LeagueSaveCatalog.remove(slug)
	quit()


func _scroll_to(section: String, offset: float) -> void:
	var screen = scene.wiki_host.screen
	if screen == null or screen.body == null:
		return
	for row in screen.body.rows():
		if str(row.get("k", "")) != "section" or str(row.get("text", "")) != section:
			continue
		var rect: Rect2 = row.get("rect", Rect2())
		screen.body.scroll_to(maxf(rect.position.y - offset, 0.0))
		break


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
