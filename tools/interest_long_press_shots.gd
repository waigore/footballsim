extends SceneTree

## Evidence capture for the long-press menu (#107).
##
## Boots the real game scene, builds a generated season, holds a club name on the
## hub, and writes the poses the gesture shows: the menu over the hub, the same
## name gold once the door followed it, and the menu over the broadcast overlay.
## Run it on a display — a headless run has no frame to read back.
##
##   xvfb-run -a godot --path . --script res://tools/interest_long_press_shots.gd

const SEED := 2032

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Long Press Season", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	season.advance()
	league.show_season(season)
	# The day the plan is on, so the first rows carry club names.
	season.save.set_date(season.record.fixtures.all(2)[0]["kickoff"])
	season.save.set_matchday(2)
	league.screen.refresh()
	await _frames(3)
	var screen: LeagueScreen = league.screen
	var zone := _name(screen)
	if zone.is_empty():
		print("EXIT the hub painted no club name")
		quit()
		return
	var club := str(zone["club_id"])
	var at: Vector2 = (zone["rect"] as Rect2).get_center()
	# What a held finger does: the press, then the clock, then the menu on top.
	screen.interest.press_at(at)
	screen.interest.tick(InterestPress.HOLD + 0.01)
	await _shot("long_press_hub")
	# The door follows the club, and the sheet repaints with its names gold.
	var vp: Vector2 = screen.design_vp()
	screen.click(screen.interest.menu.hit(screen.interest.menu.door_rect(vp).get_center(), vp))
	await _shot("long_press_followed")
	# The same hold over the broadcast overlay's scoreboard.
	scene.menus.league.close()
	scene._on_fixture_confirmed(club, _other(club))
	_kick_briefing()
	scene.paused = true
	scene.hud.queue_redraw()
	await _frames(4)
	var door := _hud_door(scene, "team_0")
	if door.size.x > 0.0:
		var hud_at: Vector2 = door.get_center()
		scene.hud.interest.press_at(hud_at)
		scene.hud.interest.tick(InterestPress.HOLD + 0.01)
		await _shot("long_press_hud")
	print("EXIT season=", season.save.slug, " interests=", season.record.interest.interests(),
		" club=", club)
	quit()

## The first club name the hub painted, in design space.
func _name(screen: LeagueScreen) -> Dictionary:
	if screen.rows_names == null:
		return {}
	for zone in screen.rows_names.zones:
		return zone
	return {}

func _other(club: String) -> String:
	for id in TeamData.team_ids():
		if str(id) != club:
			return str(id)
	return "ENG-MCI1"

func _hud_door(game, id: String) -> Rect2:
	for b in game.hud.buttons:
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

## Every watched match now opens the pre-match briefing first (#157): kick it off
## so the pose this tool captures is the match, not the briefing.
func _kick_briefing() -> void:
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")

func _shot(name: String) -> void:
	await _frames(4)
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
	print("SHOT ", name)
