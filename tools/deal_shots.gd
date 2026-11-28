extends SceneTree

## Evidence capture for the L5 deal engine (#444): the player page's TRANSFER
## block after one signed move. Run on a display.
##
##   godot --path . --script res://tools/deal_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0
##   godot --path . --script res://tools/deal_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1

const SEED := 4441
const OUT := "market-20261128-deals"

var scene = null
var design := Vector2i(1600, 900)
var scale := 1
var touch := false


func _initialize() -> void:
	_parse_args()
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
	var from_club := "ENG-ARS1"
	var to_club := "ENG-AVL1"
	var player_id := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[from_club]).get("id", ""))
	var offer := {
		"player_id": player_id, "from_club_id": from_club, "to_club_id": to_club,
		"kind": "permanent", "fee": 24000000, "wage": 100000, "years": 3, "consent": 1,
		"date": season.save.current_date(),
	}
	var signed := MarketDeals.force(season.save, offer)
	print("DEAL state=", str(signed.get("state", "")),
		" registration=", str(signed.get("registration", "")))
	var league: LeagueHost = scene.menus.league
	league.show_season(season)
	_pose(league)
	await _frames(2)
	scene.wiki_host.open_page_over_league(WikiModel.PLAYER, player_id)
	await _frames(2)
	var body = scene.wiki_host.screen.body
	_scroll_to_transfer(body)
	await _shot(OUT)
	var slug := season.save.slug
	season.close()
	LeagueSaveCatalog.remove(slug)
	quit()


func _scroll_to_transfer(body) -> void:
	for row in body.rows():
		var entry: Dictionary = row
		if str(entry.get("k", "")) == "section" and str(entry.get("text", "")) == "TRANSFER":
			var rect: Rect2 = entry["rect"]
			body.scroll_to(maxf(rect.position.y - 16.0, 0.0))
			return
	body.scroll_to(0.0)


func _parse_args() -> void:
	for raw: String in OS.get_cmdline_user_args():
		if raw.begins_with("--design="):
			var parts := raw.substr("--design=".length()).split("x")
			if parts.size() == 2:
				design = Vector2i(int(parts[0]), int(parts[1]))
		elif raw.begins_with("--scale="):
			scale = maxi(int(raw.substr("--scale=".length())), 1)
		elif raw.begins_with("--touch="):
			touch = int(raw.substr("--touch=".length())) != 0


func _pose(league: LeagueHost) -> void:
	var factor := float(scale)
	scene.chrome_scale = factor
	league.layer.transform = Transform2D.IDENTITY.scaled(Vector2(factor, factor))
	league.screen.ui_scale = factor
	league.screen.touch = touch
	league.screen.refresh()


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await _frames(6)
	var img := root.get_texture().get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var file := "%s-%d.png" % [name, img.get_width()]
	img.save_png(ProjectSettings.globalize_path("res://shots/%s" % file))
	print("WROTE res://shots/%s %dx%d" % [file, img.get_width(), img.get_height()])
