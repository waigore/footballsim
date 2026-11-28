extends SceneTree

## Evidence capture for the transfer inspector extras (#446) and clearance (#447):
## a player page's TRANSFER block after a second sale with agent, bonus, sell-on
## and solidarity, and a cross-association deal paused in clearance.
##
##   godot --path . --script res://tools/market_terms_shots.gd -- \
##     --design=1600x900 --scale=1 --touch=0
##   godot --path . --script res://tools/market_terms_shots.gd -- \
##     --design=913x411 --scale=2 --touch=1

const SEED := 4461
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
	var season := LeagueSeason.create("Terms Evidence", "generated", "fixture_days", SEED,
		["PL"], false)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	scene.menus.close()
	await _show_terms(season)
	await _clearance(season)
	var slug := season.save.slug
	season.close()
	LeagueSaveCatalog.remove(slug)
	quit()


func _show_terms(season: LeagueSeason) -> void:
	var first := _club_in("PL", 0)
	var middle := _club_in("PL", 1)
	var last := _club_in("PL", 2)
	var youth := _club_in("PL", 5)
	var player := _player_at(first)
	var birth := str(PLDatabase.row("SELECT date_of_birth FROM player WHERE id = ?;",
		[player]).get("date_of_birth", ""))
	PLDatabase.execute("DELETE FROM player_history WHERE player_id = ?;", [player])
	PLDatabase.execute(
		"INSERT INTO player_history (player_id, season_index, club_id, competition_id, kind, "
		+ "from_date, to_date) VALUES (?, 0, ?, 'PL', 'spell', ?, ?);",
		[player, youth, _aged(birth, 13), _aged(birth, 17)])
	var sold := _seal(season, first, middle, player, _deal_terms(player, {"fee": 2_000_000,
		"sell_on": 0.1}))
	print("EXIT terms first=", str(sold.get("state", "")))
	var second := _seal(season, middle, last, player, _deal_terms(player, {"fee": 8_000_000,
		"agent_fee": 800_000, "signing_bonus": 500_000}))
	print("EXIT terms second=", str(second.get("state", "")))
	scene.wiki_host.open_page(WikiModel.PLAYER, player)
	await _frames(5)
	_scroll_to_transfer()
	await _shot("market_terms_%s" % tag)


func _clearance(season: LeagueSeason) -> void:
	var from := _club_in("LL", 0)
	var to := _club_in("PL", 0)
	var player := _player_at(from)
	var deal := MarketDeals.propose(season, from, to, player, _deal_terms(player), DATE)
	var agreed := MarketDeals.agree(str(deal.get("deal", "")), DATE)
	print("EXIT clearance=", str(agreed.get("state", "")), " clears=", str(agreed.get("clears_on", "")))
	scene.wiki_host.open_page(WikiModel.PLAYER, player)
	await _frames(5)
	_scroll_to_transfer()
	await _shot("market_clearance_%s" % tag)


func _scroll_to_transfer() -> void:
	var screen = scene.wiki_host.screen
	if screen == null or screen.body == null:
		return
	screen.body.scroll_to(0.0)
	for row in screen.body.rows():
		if str(row.get("k", "")) != "section" or str(row.get("text", "")) != "TRANSFER":
			continue
		var rect: Rect2 = row.get("rect", Rect2())
		screen.body.scroll_to(maxf(rect.position.y - 120.0, 0.0))
		break


func _deal_terms(player_id: String, overrides: Dictionary = {}) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player_id)
	var terms := {
		"fee": 500_000, "wage": int(contract.get("wage", 5000)), "years": 4,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0,
	}
	for key in overrides:
		terms[key] = overrides[key]
	return terms


func _seal(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary) -> Dictionary:
	var deal := MarketDeals.propose(season, from, to, player, terms, DATE)
	MarketDeals.agree(str(deal.get("deal", "")), DATE)
	return MarketDeals.seal(str(deal.get("deal", "")), DATE)


func _club_in(competition_id: String, index: int) -> String:
	var rows := PLDatabase.rows(
		"SELECT id FROM club WHERE competition_id = ? ORDER BY id;", [competition_id])
	if rows.is_empty():
		return ""
	return str(rows[clampi(index, 0, rows.size() - 1)]["id"])


func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[club_id]).get("id", ""))


func _aged(birth: String, years: int) -> String:
	return FixtureCalendar.add_years(birth, years)


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
