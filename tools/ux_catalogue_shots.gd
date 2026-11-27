extends SceneTree

## The eleven UX VLM catalogue screens, shot once each on the real scene with
## `TypeDensity` active, so the ux-vlm PR gate has a desktop wiki image per
## screen this change touches. Type density is a raster rule that reaches every
## text surface, which is why the whole catalogue is shot rather than one screen.
##
##   xvfb-run -a --server-args="-screen 0 1920x1080x24" \
##     godot --path . --resolution 1600x900 --script res://tools/ux_catalogue_shots.gd
##
## Writes `shots/ux337_<screen>.png` (git-ignored) and prints each pose's density.

const SEED := 3370

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	await _menu()
	await _settings()
	await _quit_confirm()
	await _picker()
	await _pre_match()
	await _match_hud()
	await _match_hud_hidden()
	await _league()
	await _wiki()
	print("EXIT density=%s window=%s" % [
		str(root.oversampling_override), str(DisplayServer.window_get_size())])
	quit()

func _menu() -> void:
	scene.menus.close()
	scene.menus.open_menu()
	await _shot("main-menu")

func _settings() -> void:
	scene.menus.close()
	scene.menus.open_settings()
	await _shot("settings")

func _quit_confirm() -> void:
	scene.menus.close()
	scene.menus.open_menu()
	scene.menus.ask_quit()
	await _shot("quit-confirm")

func _picker() -> void:
	scene.menus.close()
	scene.open_select(true)
	await _shot("fixture-picker")

func _pre_match() -> void:
	scene.fixture.close()
	scene.menus.close()
	scene._on_fixture_confirmed("MUN", "MCI")
	await _frames(4)
	await _shot("pre-match")

func _match_hud() -> void:
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")
		await _frames(3)
	scene.paused = true
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _shot("match-hud")

func _match_hud_hidden() -> void:
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _shot("match-hud-hidden")
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()

func _league() -> void:
	var season := LeagueSeason.create("Catalogue Season", "generated", "fixture_days", SEED)
	if season == null:
		print("SKIP league (no season)")
		return
	league.show_season(season)
	await _shot("league-hub")
	LeagueDoors.open_table(league.screen)
	await _shot("league-table")
	LeagueDoors.open_calendar(league.screen)
	await _shot("league-calendar")
	league.close()
	await _frames(2)

func _wiki() -> void:
	scene.menus.close()
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _shot("encyclopedia")
	scene.wiki_host.close()
	await _frames(2)

func _shot(screen_id: String) -> void:
	scene.view.sync_type_density()
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
	img.save_png("res://shots/ux337_%s.png" % screen_id)
	print("SHOT %-18s %s density=%.2f" % [
		screen_id, str(img.get_size()), root.oversampling_override])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame
