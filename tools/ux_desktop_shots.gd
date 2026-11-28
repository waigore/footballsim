extends SceneTree

## The desktop poses the ux-vlm gate asks for on this PR: one 1600x900 frame per
## screen these fixes touch — the match HUD (the speed door, #265), the fixture
## picker (the chips and heading, #266), the league hub (the drawer plate, #273)
## and the encyclopedia's league page (the row pitch, #274).
##
##   godot --path . --resolution 1600x900 --script res://tools/ux_desktop_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	# ---- match-hud
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("ENG-MUN1", "ENG-MCI1")
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")
		await _frames(2)
	scene.paused = false
	scene.set_process(false)
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.match_time = 14.0
	scene.view.set_mode("highlights")
	scene.fast_mode = true
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("ux265_match_hud_desktop")
	# ---- fixture-picker
	scene.open_select(true)
	await _frames(2)
	await _shot("ux266_fixture_picker_desktop")
	scene.fixture.close()
	await _frames(2)
	# ---- league-hub, with the season's drawer out
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("UX Desktop Evidence", "generated", "fixture_days", 2026)
	if season != null:
		league.show_season(season)
		await _frames(2)
		await _shot("ux273_league_hub_desktop")
		league.screen.panel.open()
		league.screen.panel.settle()
		league.screen.refresh()
		await _frames(2)
		await _shot("ux273_league_hub_drawer_desktop")
		league.detach_season()
		league.close()
		await _frames(2)
	# ---- encyclopedia
	scene.menus.close()
	await _frames(2)
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _frames(3)
	await _shot("ux274_encyclopedia_desktop")
	scene.wiki_host.close()
	await _frames(2)
	print("EXIT vp=%s" % scene.get_viewport().get_visible_rect().size)
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(4)
	RenderingServer.force_draw(false)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	img.save_png("res://shots/%s.png" % name)
	print("SHOT shots/%s.png %s" % [name, img.get_size()])
