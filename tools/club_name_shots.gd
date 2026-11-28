extends SceneTree

## Desktop evidence for the full club name on every table surface (#407).
##
## Boots the real game scene on a 1600x900 sheet, builds a generated season so
## the tables carry a live record, and shoots the four catalogue screens this
## change touches: the league table (compact and full), the calendar, the hub
## and the encyclopedia's league page.
##
##   godot --path . --resolution 1600x900 --script res://tools/club_name_shots.gd

const SEED := 4070

var scene = null
var league: LeagueHost = null


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	await _league()
	await _wiki()
	await _phone()
	print("EXIT window=%s" % str(DisplayServer.window_get_size()))
	quit()


func _phone() -> void:
	root.size = Vector2i(914, 411)
	await _frames(3)
	scene.dev.ui_scale = 0.0
	scene.hud_scale = 1.0
	scene.chrome_scale = 1.0
	scene.touch = true
	scene.menus.sync(Transform2D.IDENTITY, 1.0, scene.touch)
	if scene.wiki_host != null:
		scene.wiki_host.screen.touch = scene.touch
		scene.wiki_host.sync_scale()
	await _frames(3)
	var season := LeagueSeason.open(LeagueSave.current.slug if LeagueSave.current != null else "")
	if season != null:
		league.show_season(season)
		await _frames(2)
		LeagueDoors.open_table(league.screen)
		league.screen.book.table.mode = LeagueTableView.COMPACT
		league.screen.refresh()
		await _shot("issue407_table_phone")
		league.close()
		await _frames(2)
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _shot("issue407_encyclopedia_phone")
	scene.wiki_host.close()
	await _frames(2)


func _league() -> void:
	var season := LeagueSeason.create("Club Names", "generated", "fixture_days", SEED)
	if season == null:
		print("SKIP league (no season)")
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 8 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _shot("issue407_hub")
	LeagueDoors.open_table(league.screen)
	league.screen.book.table.mode = LeagueTableView.FULL
	league.screen.refresh()
	await _shot("issue407_table_full")
	league.screen.book.table.mode = LeagueTableView.COMPACT
	league.screen.refresh()
	await _shot("issue407_table_compact")
	LeagueDoors.open_calendar(league.screen)
	await _shot("issue407_calendar")
	league.close()
	await _frames(2)


func _wiki() -> void:
	scene.menus.close()
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _shot("issue407_encyclopedia")
	scene.wiki_host.screen.body.scroll_to(760.0)
	await _shot("issue407_encyclopedia_results")
	scene.wiki_host.close()
	await _frames(2)


func _shot(screen_id: String) -> void:
	await _frames(5)
	RenderingServer.force_draw(false)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % screen_id)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % screen_id)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % screen_id))
	print("SHOT %-26s %s" % [screen_id, str(img.get_size())])


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
