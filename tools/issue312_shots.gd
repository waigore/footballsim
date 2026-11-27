extends SceneTree

## Evidence capture for #312: on the first day of a new season the Stats sheet
## said `No matchdays match these filters.` with ALL / ALL MONTHS selected and
## ended on a `LEADERS · GOALS` heading with no rows under it.
##
## Boots the real scene, creates a fresh season (nothing played), opens the Stats
## sheet at 1600x900 and at 3024x1648, and prints the note the sheet carries plus
## whether it painted a LEADERS caption. Then it plays a matchday and shoots the
## same sheet, where the list is empty only because the filters exclude it.
##
##   xvfb-run -a godot --path . --script res://tools/issue312_shots.gd
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
	var season := LeagueSeason.create("Stats Empty 312", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	await _frames(3)
	var screen = league.screen
	# The UX catalogue grades the league-hub surface, whose CONTINUE is the flow
	# screen's named CTA; the Stats pose is shot beside it on the evidence page.
	await _pose(Vector2i(1600, 900))
	await _shot("issue312_hub_1600")
	for size in [Vector2i(1600, 900), Vector2i(3024, 1648)]:
		await _pose(size)
		screen.click("nav:stats")
		await _frames(3)
		var tag := "%dx%d" % [size.x, size.y]
		print("STATS ", tag, " ", _read(screen))
		await _shot("issue312_stats_unplayed_%d" % size.x)
		screen.click("back")
		await _frames(2)
	# A played matchday, then a team filter that matches nothing: the list is
	# empty because of the filter, and the note may say so.
	season.advance()
	league.show_season(season)
	await _frames(3)
	screen = league.screen
	await _pose(Vector2i(1600, 900))
	screen.click("nav:stats")
	await _frames(3)
	screen.stats_filter["team"] = "NOCLUB"
	screen.refresh()
	await _frames(3)
	print("STATS filtered ", _read(screen))
	await _shot("issue312_stats_filtered_1600")
	print("EXIT season=", season.save.slug)
	quit()

## The sheet's own empty-state copy, read from the rows the screen laid.
func _read(screen) -> String:
	var note := "(no note)"
	var leaders := "(no LEADERS caption)"
	for item in screen.buttons:
		if str(item.get("kind", "")) == "note":
			note = str(item.get("label", ""))
		elif str(item.get("kind", "")) == "caption" and str(item.get("label", "")).begins_with("LEADERS"):
			leaders = str(item.get("label", ""))
	return "note=%s leaders=%s played=%d" % [note, leaders, int(screen.current_view().get("played", -1))]

## Set the window the shot is taken in, then settle the shell on it.
func _pose(size: Vector2i) -> void:
	DisplayServer.window_set_size(size)
	root.size = size
	await _frames(4)
	scene._sync_overlay_scale()
	scene.menus.league.screen.refresh()
	await _frames(4)

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
