extends SceneTree

## Evidence capture for the product-wide sheet chrome (#163): BACK top-left on
## every sheet, CONTINUE / KICK OFF top-right, the table's two readings in its
## bottom bar, and BACK on the podium.
##
## Boots the real game, builds a generated season, plays two matchdays, and walks
## every surface the issue names on a desktop window and at handheld scale.
## Writes a PNG per pose into `res://shots/` and prints each pose's chrome
## geometry so the evidence page carries numbers as well as pixels.
##
##   godot --path . --resolution 1600x900 --script res://tools/sheet_chrome_shots.gd

const SEED := 1630

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	# Settings and the fixture picker are menu-side sheets: shoot them cold, the
	# way a player reaches them, before a season is open.
	scene.menus.open_settings()
	await _shot("issue163_settings")
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	await _shot("issue163_settings_phone")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	scene.menus.open_menu()
	scene.open_select(true)
	await _shot("issue163_picker")
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	await _shot("issue163_picker_phone")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	scene._close_select()
	scene.menus.close()
	var season := LeagueSeason.create("Chrome Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	# Two played matchdays, so the report, the roundup and the table all have rows.
	season.advance()
	var played: Array = season.advance().get("played", [])
	league.show_season(season)
	await _shot("issue163_hub")

	league.screen.click("table")
	await _shot("issue163_table")
	league.screen.click("back")
	league.screen.click("calendar")
	await _shot("issue163_calendar")
	league.screen.click("back")
	league.screen.click("system")
	await _shot("issue163_system")
	league.screen.click("back")

	# A settled fixture, then the whole matchday as a roundup.
	if not played.is_empty():
		var first: Dictionary = played[0]
		league.screen.show_report(str((first.get("fixture", {}) as Dictionary).get("id", "")))
		await _shot("issue163_report")
		var reports: Array = []
		for entry in played:
			reports.append(season.report(str((entry.get("fixture", {}) as Dictionary).get("id", ""))))
		league.screen.show_roundup(reports)
		await _shot("issue163_roundup")
		league.screen.click("back")

	# The pre-match briefing, desktop and phone.
	var fixture: Dictionary = {}
	for fx in season.record.fixtures.pending_upto("2027-06-01"):
		fixture = fx
		break
	if not fixture.is_empty():
		season.set_watch(str(fixture["id"]), true)
		league.screen.refresh()
		league.screen.click("fixture:" + str(fixture["id"]))
		# SKIP holds the briefing: a ten-second auto-advance would start the match
		# while the next pose is being captured.
		scene.prematch.screen.hold()
		await _shot("issue163_prematch")
		scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
		scene._sync_overlay_scale()
		await _shot("issue163_prematch_phone")
		scene.prematch.close()
		scene.dev.ui_scale = 0.0
		scene._sync_overlay_scale()
		if not scene.menus.league_active():
			league.show_season(season)

	# The hub and the table at handheld scale.
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	league.screen.refresh()
	await _shot("issue163_hub_phone")
	league.screen.click("table")
	await _shot("issue163_table_phone")
	league.screen.click("back")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()

	# Season complete: the podium carries its own BACK.
	season.save.set_status("complete")
	season.save.reload()
	league.show_season(season)
	await _shot("issue163_podium")
	print("EXIT season=", season.save.slug)
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
	# Force the draw stage before reading back: a queued redraw that has not
	# reached it saves the previous pose, and a window the OS has occluded may
	# not draw on its own.
	RenderingServer.force_draw(false)
	_report(name)
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
	print("SHOT %s %dx%d hash=%d" % [name, img.get_width(), img.get_height(), hash(img.get_data())])

## The corners each pose actually laid out, so the page can cite numbers.
func _report(name: String) -> void:
	var out: Array = []
	if league != null and league.screen != null and scene.menus.league_active():
		out.append("mode=" + str(league.screen.mode))
		for item in league.screen.buttons:
			var id := str(item["id"])
			if id == "back" or id == "continue" or id == "kick" or id.begins_with("tbl:mode:"):
				out.append("%s=%s" % [id, str(item["rect"])])
	if scene.prematch != null and scene.prematch.screen != null and scene.prematch.screen.is_open():
		var pre: PreMatchScreen = scene.prematch.screen
		for b in pre.layout(pre.design_vp())["buttons"]:
			out.append("prematch:%s=%s" % [str(b["id"]), str(b["rect"])])
	print("CHROME ", name, " ", " ".join(PackedStringArray(out)))
