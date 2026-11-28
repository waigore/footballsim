extends SceneTree

## Evidence capture for the deal engine (#444): the player page's TRANSFER block
## after one domestic move has been signed, at the desktop design space and at a
## handset pose.
##
##   godot --path . --script res://tools/deal_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0
##   godot --path . --script res://tools/deal_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1

const SEED := 4441
const DATE := "2026-08-20"

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
	var season := LeagueSeason.create("Deal Evidence", "generated", "fixture_days", SEED,
		["PL"], false)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var from := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var to := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1 OFFSET 1;").get(
		"id", ""))
	var player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;", [from]).get(
		"id", ""))
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	var terms := {"fee": 24_000_000, "wage": wage, "years": 4, "agent_fee": 1_200_000}
	var deal := MarketDeals.propose(season, from, to, player, terms, DATE)
	var agreed := MarketDeals.agree(str(deal.get("deal", "")), DATE)
	var done := MarketDeals.seal(str(deal.get("deal", "")), DATE)
	print("EXIT deal=", str(agreed.get("state", "")), " -> ", str(done.get("state", "")),
		" reason=", str(done.get("reason", "")))
	scene.menus.close()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.PLAYER, player)
	await _frames(5)
	var screen = scene.wiki_host.screen
	if screen != null and screen.body != null:
		screen.body.scroll_to(0.0)
		await _frames(2)
		for row in screen.body.rows():
			if str(row.get("k", "")) != "section" or str(row.get("text", "")) != "TRANSFER":
				continue
			var rect: Rect2 = row.get("rect", Rect2())
			screen.body.scroll_to(maxf(rect.position.y - 120.0, 0.0))
			break
		await _frames(3)
	await _shot("market_deals_%s" % tag)
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
			scale = maxi(int(raw.substr(8)), 1)
		elif raw == "--touch=1":
			touch = true


func _shot(name: String) -> void:
	await _frames(3)
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT %s %dx%d" % [name, img.get_width(), img.get_height()])


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
