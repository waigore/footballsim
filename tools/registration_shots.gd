extends SceneTree

## Evidence capture for the club page's registration block (#448): the SQUAD
## list's LIST flag, the REGISTRATION slots/homegrown block and an ineligible
## permit flag, at the desktop design space and at a handset pose.
##
##   godot --path . --script res://tools/registration_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0
##   godot --path . --script res://tools/registration_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1

const SEED := 4481

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
	var season := LeagueSeason.create("Registration Evidence", "generated", "fixture_days", SEED,
		["PL"], false)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var club_id := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	_inject_ineligible(club_id)
	scene.menus.close()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.TEAM, club_id)
	await _frames(5)
	_scroll_to("SQUAD", 60.0)
	await _frames(3)
	await _shot("market_registration_squad_%s" % tag)
	_scroll_to("REGISTRATION", 220.0)
	await _frames(3)
	await _shot("market_registration_block_%s" % tag)
	var counts := MarketRegistration.tally(club_id, "PL")
	print("EXIT ", tag, " club=", club_id, " counts=", JSON.stringify(counts),
		" state=", MarketRegistration.state_of(club_id, "PL"))
	var slug := season.save.slug
	season.close()
	LeagueSaveCatalog.remove(slug)
	quit()


func _inject_ineligible(club_id: String) -> void:
	var weak := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "AND nationality IN ('Brazil', 'Argentina', 'Senegal', 'Morocco', 'Japan', "
		+ "'South Korea', 'Nigeria', 'Ghana', 'Colombia', 'Mexico', 'USA', 'Uruguay') "
		+ "ORDER BY ovr LIMIT 1;", [club_id]).get("id", ""))
	if weak == "":
		return
	PLDatabase.execute("UPDATE player SET club_id = ?, homegrown_club_id = '' WHERE id = ?;",
		[club_id, weak])
	MarketRegistration.register(weak, club_id, "PL", "permanent", "",
		LeagueSave.current.season_index(), "2026-08-20")
	PLRepository.shared().invalidate()


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


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
