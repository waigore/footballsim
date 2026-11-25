extends SceneTree

## Evidence capture for issue #180: RESULTS carries the hub's CONTINUE in the
## hub's corner, and no header door ever covers the page title or its kicker.
##
## Boots the real game, builds a generated season with a long name (the name is
## the hub's title, so a narrow window forces the title into the lane the doors
## leave), settles a fixture day, then walks the RESULTS sheet at desktop size,
## at the handheld design scale and in a narrow window. Each pose prints the
## header geometry it laid out, so the page carries numbers as well as pixels.
##
##   godot --path . --resolution 1600x900 --script res://tools/league_results_continue_shots.gd

const SEED := 1800
const NAME := "Manchester Derby League"

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	var season := LeagueSeason.create(NAME, "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	await _shot("issue-180-hub-desktop")
	# CONTINUE settles the day's AUTO fixtures and lands on its results.
	league.screen.click("continue")
	print("RESULTS mode=", league.screen.mode, " rows=", league.screen.roundup.size(),
		" day=", _roundup_day())
	await _shot("issue-180-results-desktop")

	# Handheld design space: one density point per design unit, 730x411.
	_scale_to(411.0)
	league.screen.refresh()
	await _shot("issue-180-results-phone")
	league.screen.click("back")
	await _shot("issue-180-hub-phone")

	# A design space narrower than a phone: the title has to fit the lane the
	# doors leave, so this is the stress pose that would paint the name under
	# CONTINUE if the header never fitted it.
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 240.0
	scene._sync_overlay_scale()
	league.screen.refresh()
	await _shot("issue-180-hub-narrow")
	print("EXIT narrow_vp=", league.screen.design_vp())
	quit()

func _scale_to(design_h: float) -> void:
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / design_h
	scene._sync_overlay_scale()

func _roundup_day() -> String:
	if league.screen.roundup.is_empty():
		return ""
	return str((league.screen.roundup[0].get("fixture", {}) as Dictionary).get("kickoff", ""))

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
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
	print("SHOT %s %dx%d" % [name, img.get_width(), img.get_height()])

## The header band each pose actually laid out: the doors, and the fitted title
## and caption they leave room for.
func _report(name: String) -> void:
	var vp: Vector2 = league.screen.design_vp()
	var bold: Font = UiChrome.fonts()["bold"]
	var out: Array = ["vp=%s" % vp]
	var cont := LeagueExtra.primary_rect(vp)
	for item in league.screen.buttons:
		if str(item["id"]) in ["back", "continue"]:
			out.append("%s=%s" % [str(item["id"]), str(item["rect"])])
	if league.screen.mode == LeagueScreen.MODE_HUB:
		var st: Dictionary = league.screen.season.state()
		var label: String = FixtureCalendar.day_label(str(st.get("date", "")))
		var rest := " · GW %d · %d OF %d PLAYED" % [int(st.get("matchday", 1)),
			int(st.get("played", 0)), int(st.get("total", 0))]
		var band := LeagueExtra.header_band(vp, bold, NAME, label + rest, cont.size.x + 12.0)
		out.append("title=%s" % str(band["title"]))
		out.append("title_rect=%s" % str(band["title_rect"]))
		out.append("caption_rect=%s" % str(band["caption_rect"]))
	else:
		var caption: String = FixtureCalendar.day_label(_roundup_day())
		var band := LeagueExtra.header_band(vp, bold, "RESULTS", caption, cont.size.x + 12.0)
		out.append("title=%s" % str(band["title"]))
		out.append("title_rect=%s" % str(band["title_rect"]))
		out.append("caption=%s" % str(band["caption"]))
		out.append("caption_rect=%s" % str(band["caption_rect"]))
	print("CHROME ", name, " ", " ".join(PackedStringArray(out)))
