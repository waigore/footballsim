extends SceneTree

## Evidence capture for #310: on a desktop build the System sheet's ADVANCE row
## still said `tap to switch to every day` and the club long-press popup still
## said `TAP ELSEWHERE TO CLOSE`, while the rest of the league chrome had split
## TAP/CLICK at #278.
##
## Boots the real scene, opens a generated season, and shoots the two loci on a
## desktop sheet and again in the phone design space. It prints the copy each
## pose paints, and the device the popup read, so the split is read back rather
## than eyeballed.
##
##   xvfb-run -a godot --path . --script res://tools/issue310_shots.gd
##
## Writes PNGs into `res://shots/` (git-ignored).

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	if league == null:
		print("EXIT no league host")
		quit()
		return
	var season := LeagueSeason.create("Pointer Verbs 310", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	await _frames(3)
	var screen = league.screen
	# The UX catalogue grades the league-hub surface, whose CONTINUE is the flow
	# screen's named CTA; the two loci are shot beside it on the evidence page.
	await _shot("issue310_hub_desktop")
	# 1. The System sheet's ADVANCE row: desktop, then the phone design space.
	screen.click("nav:system")
	await _frames(3)
	print("SYSTEM desktop hint=", _advance_hint(screen))
	await _shot("issue310_system_desktop")
	screen.touch = true
	screen.refresh()
	await _frames(3)
	print("SYSTEM phone hint=", _advance_hint(screen))
	await _shot("issue310_system_phone")
	screen.touch = false
	screen.refresh()
	await _frames(2)
	# 2. The club long-press popup's footer: a menu raised on the same sheet.
	_open_menu(screen)
	print("POPUP desktop footer=", screen.interest.menu.close_hint(),
		" touch=", screen.interest.menu.touch)
	await _shot("issue310_popup_desktop")
	screen.touch = true
	screen.refresh()
	await _frames(2)
	_open_menu(screen)
	print("POPUP phone footer=", screen.interest.menu.close_hint(),
		" touch=", screen.interest.menu.touch)
	await _shot("issue310_popup_phone")
	screen.touch = false
	screen.interest.close()
	print("EXIT season=", season.save.slug)
	quit()

## Raise the popup on a real club name, the way a long press does.
func _open_menu(screen) -> void:
	if not screen.interest.open("MUN", Vector2(360.0, 300.0)):
		print("POPUP could not be raised")
	screen.menu_layer.queue_redraw()

## The ADVANCE row's own hint copy, read from the rows the screen laid.
func _advance_hint(screen) -> String:
	for item in screen.buttons:
		if str(item.get("id", "")) == "sys:advance":
			return str(item.get("hint", ""))
	return "(no sys:advance row)"

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
