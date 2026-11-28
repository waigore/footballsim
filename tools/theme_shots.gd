extends SceneTree

## One 1600x900 frame per player-facing surface the shared Theme touches, for
## the ux-vlm gate: the menu shell, settings, the quit confirm, the fixture
## picker, the pre-match briefing, the league hub and table, the encyclopedia
## and the broadcast HUD.
##
##   godot --path . --resolution 1600x900 --script res://tools/theme_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.set_process(false)
	# ---- main menu
	scene.menus.open_menu()
	await _shot("ui512_main_menu_desktop")
	# ---- settings
	scene.menus.open_settings()
	await _shot("ui512_settings_desktop")
	# ---- quit confirm
	scene.menus.ask_quit()
	await _shot("ui512_quit_confirm_desktop")
	scene.menus.shell.cancel_confirm()
	await _frames(2)
	# ---- fixture picker
	scene.menus.close()
	scene.open_select(true)
	await _frames(2)
	await _shot("ui512_fixture_picker_desktop")
	scene.fixture.close()
	await _frames(2)
	# ---- pre-match briefing
	scene._on_fixture_confirmed("ENG-MUN1", "ENG-MCI1")
	await _frames(3)
	if scene.prematch != null and scene.prematch.is_open():
		await _shot("ui512_pre_match_desktop")
		scene.prematch.close()
		await _frames(2)
	# ---- league hub
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("UI 512 Theme Evidence", "generated", "fixture_days", 2026)
	if season != null:
		league.show_season(season)
		await _frames(2)
		await _shot("ui512_league_hub_desktop")
		# ---- league table
		LeagueDoors.open_table(league.screen)
		await _frames(2)
		await _shot("ui512_league_table_desktop")
		# ---- league calendar
		league.screen.mode = LeagueScreen.MODE_CALENDAR
		league.screen.refresh()
		await _frames(2)
		await _shot("ui512_league_calendar_desktop")
		league.detach_season()
		league.close()
		await _frames(2)
	# ---- encyclopedia
	scene.menus.close()
	await _frames(2)
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _frames(3)
	await _shot("ui512_encyclopedia_desktop")
	scene.wiki_host.close()
	await _frames(2)
	# ---- broadcast HUD
	scene.hud_layer.visible = true
	scene.paused = false
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.match_time = 14.0
	scene.view.set_mode("highlights")
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("ui512_match_hud_desktop")
	# ---- broadcast HUD hidden
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("ui512_match_hud_hidden_desktop")
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
