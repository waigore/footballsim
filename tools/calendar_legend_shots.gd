extends SceneTree

## Evidence capture for the calendar's day-counter legend (#382).
##
## Boots the real game scene, opens a generated season on its calendar and
## shoots the sheet at the desktop size and at the two handset sizes, printing
## the month label, the legend and the month doors so the geometry can be
## checked against the pixels. Writes `res://shots/calendar_legend_<pose>.png`.
##
##   godot --path . --resolution 1600x900 --script res://tools/calendar_legend_shots.gd

const SEED := 3820

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Calendar Legend Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("SKIP no season")
		quit()
		return
	league.show_season(season)
	await _frames(3)
	LeagueDoors.open_calendar(league.screen)
	await _frames(3)
	await _desktop(league.screen)
	await _phone(league.screen)
	await _short(league.screen)
	league.close()
	await _frames(2)
	print("EXIT")
	quit()


func _desktop(screen) -> void:
	await _scale(0.0)
	await _report("desktop_1600", screen)
	await _shot("calendar_legend_1600")


func _phone(screen) -> void:
	await _scale(maxf(scene.get_viewport().get_visible_rect().size.y / 411.0, 1.0))
	await _report("phone_411", screen)
	await _shot("calendar_legend_411")


func _short(screen) -> void:
	await _scale(maxf(scene.get_viewport().get_visible_rect().size.y / 360.0, 1.0))
	await _report("phone_360", screen)
	await _shot("calendar_legend_360")


func _scale(ui_scale: float) -> void:
	scene.dev.ui_scale = ui_scale
	scene._sync_overlay_scale()
	await _frames(3)
	var screen = scene.menus.league.screen
	if screen != null and screen.is_open():
		screen.refresh()
		await _frames(3)


func _report(name: String, screen) -> void:
	var vp: Vector2 = screen.design_vp()
	var view: Dictionary = LeagueView.build(screen)
	var fonts: Dictionary = UiChrome.fonts()
	var month: String = LeagueMonth.label(str(view.get("month", "")))
	var month_w: float = UiChrome.text_width(fonts["bold"], month, 13)
	var legend: Dictionary = LeagueCalendarView.legend_rect(vp, view, fonts)
	var doors: Array = LeagueCalendarView.month_door_rects(vp, screen.touch)
	print("LEGEND %s vp=%s touch=%s month=%s %.1f..%.1f legend=%s %s doors=%.1f grid=%.1f" % [
		name, str(vp), str(screen.touch), month, 24.0, 24.0 + month_w,
		str(legend.get("text", "(none)")), str(legend.get("rect", Rect2())),
		(doors[0] as Rect2).position.x, LeagueCalendarView.grid_top(screen.touch)])


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
	print("SHOT shots/%s.png %s" % [name, str(img.get_size())])