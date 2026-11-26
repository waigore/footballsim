extends SceneTree

## Evidence capture for issue #203: the encyclopedia's footer names only gestures
## the surface in front of the player can take.
##
## Boots the real game scene at the design space a 2400x1080 handset uses, opens
## the encyclopedia over a league season, and shoots:
##
##   * the league table on the phone: touch copy, no keys in it,
##   * the top of a club page, where the rows on screen are values, not links,
##   * the same club page scrolled onto its squad, where rows open players,
##   * the desktop sheet for the same pages, which keeps its keys.
##
## Writes a PNG per pose into `res://shots/` and prints the geometry it shot.
## Run it on a display; a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/wiki_footer_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var season := LeagueSeason.create("Footer Evidence", "generated", "fixture_days", 203)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	scene.menus.league.show_season(season)
	# A 2400x1080 handset at 420 dpi reads a 1096x493 design space.
	await _design(Vector2(1096.0, 493.0), true)
	scene.wiki_host.open_page_over_league(WikiModel.LEAGUE, "")
	await _frames(4)
	_report("phone league table", scene.wiki_host.screen)
	await _capture("issue203_phone_league")
	# A club page: its first screen is the record and the tactical profile.
	scene.wiki_host.screen.open(WikiModel.TEAM, "MUN")
	await _frames(4)
	scene.wiki_host.screen.body.scroll_to(0.0)
	await _frames(3)
	_report("phone club page top", scene.wiki_host.screen)
	await _capture("issue203_phone_club_top")
	# The squad below it carries the player links.
	scene.wiki_host.screen.body.scroll_to(520.0)
	await _frames(4)
	_report("phone club page squad", scene.wiki_host.screen)
	await _capture("issue203_phone_club_squad")
	# The same pages on a desktop window, which has a keyboard to name.
	await _design(Vector2(1600.0, 900.0), false)
	scene.wiki_host.screen.open(WikiModel.LEAGUE, "")
	await _frames(4)
	_report("desktop league table", scene.wiki_host.screen)
	await _capture("issue203_desktop_league")
	scene.wiki_host.screen.open(WikiModel.TEAM, "MUN")
	await _frames(4)
	_report("desktop club page top", scene.wiki_host.screen)
	await _capture("issue203_desktop_club_top")
	print("EXIT done")
	quit()

## Put the chrome layer in a design space: the wiki reads `ui_scale` against the
## window, so the layer scale is the window divided by the design width.
func _design(vp: Vector2, touch: bool) -> void:
	var scale: float = scene.get_viewport().get_visible_rect().size.x / vp.x
	scene.dev.ui_scale = scale
	scene._sync_overlay_scale()
	scene.touch = touch
	if scene.wiki_host != null:
		scene.wiki_host.screen.touch = touch
		scene.wiki_host.sync_scale()
	await _frames(4)
	print("DESIGN %s scale %.3f touch %s -> %s" % [str(vp), scale, str(touch), str(scene.wiki_host.screen.design_vp())])

## What the footer would say, from the same three facts the paint reads.
func _report(label: String, screen) -> void:
	var can_open: bool = screen.body != null and screen.body.has_open_row_in_view()
	var can_scroll: bool = screen.body != null and screen.body.max_scroll() > 0.0
	print("FOOTER %s touch=%s open=%s scroll=%s text=%s" % [
		label, str(screen.touch), str(can_open), str(can_scroll),
		WikiChrome.footer_hint(bool(screen.touch), can_open, can_scroll)])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _capture(name: String) -> void:
	await _frames(3)
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