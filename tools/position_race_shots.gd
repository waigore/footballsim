extends SceneTree

## Evidence capture for the club page's season position race (DR-20261128-10).
##
## Boots the real game scene, builds a generated season, plays ten matchdays,
## opens the league leader's club page and scrolls its body to the chart, then
## shoots the desktop size and the two handset poses. Each pose prints the
## chart's laid rect and the days it carries, so the pixels can be checked
## against the geometry. Writes `res://shots/position_race_<pose>.png`.
##
##   godot --path . --resolution 1600x900 --script res://tools/position_race_shots.gd

const SEED := 1128

var scene = null
var season: LeagueSeason = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	season = LeagueSeason.create("Position Race Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("SKIP no season")
		quit()
		return
	for i in range(10):
		season.advance()
	scene.menus.league.show_season(season)
	await _frames(3)
	var leader := str((LeagueLedger.table("PL")[0] as Dictionary)["club_id"])
	scene.wiki_host.open_page_over_league(WikiModel.TEAM, leader)
	await _frames(3)
	print("CLUB %s" % leader)
	await _pose("desktop_1600", 0.0)
	await _pose("phone_411", maxf(scene.get_viewport().get_visible_rect().size.y / 411.0, 1.0))
	await _pose("phone_360", maxf(scene.get_viewport().get_visible_rect().size.y / 360.0, 1.0))
	scene.wiki_host.close()
	season.close()
	await _frames(2)
	print("EXIT")
	quit()


func _pose(name: String, ui_scale: float) -> void:
	scene.dev.ui_scale = ui_scale
	scene._sync_overlay_scale()
	scene.wiki_host.sync_scale()
	scene.wiki_host.screen._refresh()
	await _frames(3)
	var screen = scene.wiki_host.screen
	var spark := {}
	for row in screen.body.rows():
		if str(row["k"]) == "spark":
			spark = row
	if spark.is_empty():
		print("RACE %s none" % name)
		await _shot("position_race_" + name)
		return
	screen.body.scroll_to(maxf((spark["rect"] as Rect2).position.y - 120.0, 0.0))
	await _frames(3)
	print("RACE %s vp=%s compact=%s rect=%s scroll=%.1f" % [
		name, str(screen.design_vp()), str(screen.is_compact()), str(spark["rect"]),
		screen.body.scroll])
	await _shot("position_race_" + name)


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
