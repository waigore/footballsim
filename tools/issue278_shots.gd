extends SceneTree

## Evidence capture for the league chrome's pointer words and the stats stepper
## (#278, #279, #280, #281): the picker's derived league-key legend, the hub and
## table footers on desktop, the Load League row's status copy and the stats
## month stepper. Also shoots a full desktop match HUD frame for the UX VLM
## catalogue baseline (#282).
##
## Writes a PNG per pose into `res://shots/` and prints the copy each pose shows.
## Run it on a display:
##
##   godot --path . --resolution 1600x900 --script res://tools/issue278_shots.gd

const SEED := 2780

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	# 1. The fixture picker: its footer legend, derived from the chips it draws.
	scene.open_select(true)
	await _shot("issue278_picker_footer")
	print("PICKER chips=", LeagueChrome.competition_rows().size(),
		" legend=", LeagueChrome.picker_league_keys(LeagueChrome.competition_rows()))
	scene._close_select()
	# 2. A season with the four leagues a save carries, some rounds played so the
	# hub's suggest hint is up and the table has a shape.
	var season := LeagueSeason.create("Chrome Copy", "generated", "fixture_days", SEED,
		["PL", "LL", "BL", "BL2"])
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while season.record.fixtures.completed_matchdays() < 6 and guard < 20:
		season.advance()
		guard += 1
	league.show_season(season)
	await _frames(3)
	await _shot("issue278_hub_desktop")
	print("HUB hint=", LeagueSheet.plan_hint(false), " can_suggest=",
		bool(season.state().get("can_suggest", false)))
	league.screen.click("table")
	await _shot("issue278_table_desktop")
	print("TABLE sentence=", LeagueTableChrome.sentence(false))
	league.screen.click("back")
	league.screen.click("nav:stats")
	await _shot("issue278_stats_desktop")
	# The phone sheet keeps TAP: the same poses in the handset design space.
	league.screen.touch = true
	league.screen.refresh()
	league.screen.click("back")
	league.screen.click("table")
	await _shot("issue278_table_phone")
	print("TABLE phone sentence=", LeagueTableChrome.sentence(true))
	league.screen.touch = false
	league.screen.click("back")
	league.screen.refresh()
	# 3. Load League: the save row's status copy.
	var slug := str(season.save.slug)
	league.close()
	if not league.is_open():
		print("closed the season")
	scene.menus.league.open_load()
	await _frames(3)
	league.screen.refresh()
	await _shot("issue278_load_desktop")
	print("LOAD status label=", LeagueStartSheet.status_label("in_progress"))
	scene.menus.league.close()
	# 4. The match HUD at desktop, full frame (the UX VLM catalogue baseline).
	scene.menus.open_menu()
	scene._on_fixture_confirmed("MUN", "MCI")
	scene.paused = true
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.hud.set_hud_visible(true, true)
	await _frames(4)
	await _shot("issue282_hud_desktop")
	print("EXIT save=", slug)
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(3)
	RenderingServer.force_draw(false)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT ", name, " ", img.get_size())
