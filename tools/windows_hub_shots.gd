extends SceneTree


const SEED := 4430
const SHOTS := "res://shots"

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Window Evidence", "generated", "fixture_days", SEED, ["PL"])
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var screen: LeagueScreen = league.screen
	await _shot("windows_hub_open", _plain.bind(screen))
	season.save.set_date("2026-09-02")
	screen.refresh()
	await _shot("windows_hub_closed", _plain.bind(screen))
	season.save.set_date("2027-07-05")
	screen.refresh()
	await _shot("windows_hub_generated", _plain.bind(screen))
	season.save.set_date("2026-09-02")
	scene.dev.ui_scale = maxf(scene.get_viewport().get_visible_rect().size.y / 411.0, 1.0)
	scene._sync_overlay_scale()
	screen.refresh()
	await _shot("windows_hub_closed_phone", _plain.bind(screen))
	print("EXIT done")
	quit()


func _plain(_screen: LeagueScreen) -> void:
	pass


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String, pose: Callable) -> void:
	pose.call()
	await _frames(6)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SHOTS))
	img.save_png(ProjectSettings.globalize_path("%s/%s.png" % [SHOTS, name]))
	print("SHOT ", name, " ", img.get_size())
