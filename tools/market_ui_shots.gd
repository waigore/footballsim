extends SceneTree

## Evidence capture for the market surfaces (#452, #453): the transfer hub, a
## deal inspector, the news sheet and the club page's squad list. Boots the real
## game scene on a display and writes PNGs into `res://shots/`.
##
##   godot --path . --script res://tools/market_ui_shots.gd -- --design=1600x900 --scale=1
##   godot --path . --script res://tools/market_ui_shots.gd -- --design=913x411 --scale=2 --touch=1

const SEED := 7453
const DATE := "2026-08-20"
const CLOSED := "2026-12-20"

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
	var season := LeagueSeason.create("Market UI Evidence", "generated", "fixture_days", SEED,
		["PL"], false)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var clubs: Array = []
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;"):
		clubs.append(str(row["id"]))
	var deal_ids: Array = []
	for i in range(8):
		var from := str(clubs[i % clubs.size()])
		var to := str(clubs[(i + 1) % clubs.size()])
		var player := str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
			[from]).get("id", ""))
		if player == "":
			continue
		var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
		var terms := {"fee": 5_000_000 + i * 500_000, "wage": wage, "years": 3,
			"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}
		var deal := str(MarketDeals.propose(season, from, to, player, terms, DATE).get("deal", ""))
		if deal == "":
			continue
		MarketDeals.negotiate(deal, DATE)
		deal_ids.append(deal)
		if i == 0:
			MarketDeals.block(deal, DATE, "evidence veto")
		elif i == 3:
			MarketDeals.force(deal, DATE)
		else:
			MarketDeals.agree(deal, DATE)
			MarketDeals.seal(deal, DATE)
	var doomed_from := str(clubs[5 % clubs.size()])
	var doomed_player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
		[doomed_from]).get("id", ""))
	if doomed_player != "":
		var doomed := str(MarketDeals.propose(season, doomed_from, str(clubs[0]), doomed_player,
			{"fee": 6_000_000,
				"wage": int(MarketDealRecords.active_contract(doomed_player).get("wage", 5000)),
				"years": 2, "agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0},
			CLOSED).get("deal", ""))
		MarketDeals.agree(doomed, CLOSED)
	var league: LeagueHost = scene.menus.league
	league.show_season(season)
	await _frames(4)
	league.screen.touch = touch
	await _shot("market_league_hub_%s" % tag)
	league.screen.click("nav:transfers")
	await _frames(4)
	print("POSE hub mode=", league.screen.mode)
	await _shot("market_hub_%s" % tag)
	var signed := ""
	for item in league.screen.buttons:
		var id := str(item["id"])
		if id.begins_with("deal:") and signed == "":
			signed = id
	if signed == "" and not deal_ids.is_empty():
		signed = "deal:" + str(deal_ids[deal_ids.size() - 1])
	print("DEBUG buttons=", league.screen.buttons.size(), " signed=", signed)
	if signed != "":
		LeagueDoors.press(league.screen, signed)
		await _frames(4)
		print("POSE deal mode=", league.screen.mode)
		await _shot("market_deal_%s" % tag)
		LeagueDoors.press(league.screen, "back")
		await _frames(3)
	LeagueDoors.press(league.screen, "transfer:news")
	await _frames(4)
	print("POSE news mode=", league.screen.mode)
	await _shot("market_news_%s" % tag)
	LeagueDoors.press(league.screen, "back")
	await _frames(3)
	var club_id := str(clubs[0])
	league.close()
	scene.menus.close()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.TEAM, club_id)
	await _frames(5)
	var screen = scene.wiki_host.screen
	if screen != null and screen.body != null:
		screen.body.scroll_to(0.0)
		for row in screen.body.rows():
			if str(row.get("k", "")) != "section" or str(row.get("text", "")) != "SQUAD LIST":
				continue
			var rect: Rect2 = row.get("rect", Rect2())
			screen.body.scroll_to(maxf(rect.position.y - 120.0, 0.0))
			break
		await _frames(3)
	await _shot("market_squad_%s" % tag)
	print("EXIT tag=", tag, " club=", club_id, " deals=", deal_ids.size(),
		" news=", MarketNews.count(season.save.season_index()))
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
