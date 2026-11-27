extends SceneTree

## Evidence capture for #323: the season hub reads as Today's Fixtures.
##
## Shoots the hub on a one-league season and on a two-league one, desktop and at
## handset scale, and prints what each pose actually paints — the header band's
## title and caption, the body's hint line, and every league heading with the
## gameweek it carries — so the capture is read back rather than eyeballed.
##
##   godot --path . --resolution 1600x900 --script res://tools/issue323_shots.gd

const SEED := 3230

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	scene.menus.close()
	# 1. A save named exactly what the old default was: the hub must still say
	#    Today's Fixtures, never the save.
	var one := LeagueSeason.create("League 1", "generated", "fixture_days", SEED)
	if one == null:
		print("EXIT could not create a season")
		quit()
		return
	# Six rounds behind it, so the SUGGEST WATCHES door is up and the body's hint
	# line really paints (it waits for five completed rounds).
	var guard := 0
	while one.record.fixtures.completed_matchdays() < 6 and guard < 12:
		one.advance()
		guard += 1
	league.show_season(one)
	await _shot("issue323_hub_single_league")
	_read("single league desktop")
	# 2. The same fixtures at 411 dp, a handset's design height.
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	league.screen.refresh()
	await _shot("issue323_hub_single_league_phone")
	_read("single league phone")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	# 3. Two leagues on one day: every group keeps its own heading.
	league.close()
	var many := LeagueSeason.create("My League Sim", "generated", "fixture_days", SEED + 1, ["PL", "LL"])
	if many == null:
		print("EXIT could not create a multi-league season")
		quit()
		return
	league.show_season(many)
	await _shot("issue323_hub_multi_league")
	_read("multi league desktop")
	# 4. The New League wizard's opening name.
	league.close()
	scene.menus.league.open_wizard()
	await _frames(3)
	league.screen.refresh()
	await _shot("issue323_wizard_default_name")
	print("WIZARD default name=", str(league.screen.wizard["name"]))
	league.close()
	print("EXIT single=", one.save.slug, " multi=", many.save.slug)
	quit()

## What the hub on screen really paints: the header band, the body line and each
## league heading. Read from the sheet's own state, not from the PNG.
func _read(label: String) -> void:
	var state: Dictionary = league.screen.current_view()
	var vp: Vector2 = league.screen.design_vp()
	var bold: Font = UiChrome.fonts()["bold"]
	var band := LeagueExtra.header_band(vp, bold, LeagueSheet.HUB_TITLE, LeagueSheet.hub_caption(state),
		LeagueExtra.primary_rect(vp).size.x + 12.0, false)
	print("HUB %s: title=[%s] caption=[%s] hint=[%s]" % [label, str(band["title"]),
		str(band["caption"]), LeagueSheet.body_hint(state)])
	var heads: Array = []
	for item in league.screen.hub.hub_layout(vp, state):
		if str(item.get("kind", "")) == "league_head":
			heads.append("%s GW %d" % [str(item.get("competition", "")), int(item.get("matchday", 1))])
	print("HUB %s: headings=[%s]" % [label, ", ".join(PackedStringArray(heads))])

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
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	print("SHOT ", name, " ", img.get_size())
