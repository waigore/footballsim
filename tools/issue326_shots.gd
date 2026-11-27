extends SceneTree

## Evidence capture for #326: Results CONTINUE returns to Today's Fixtures.
##
## Walks the real season screen: Continue on the hub settles the day and shows
## its roundup, then Continue on Results leaves that reading for the next day's
## hub — with its fixtures and AUTO/WATCH chips — and settles nothing. Each pose
## is read back from the screen's own state, so the log says what was painted and
## what the clock did, not what the pictures look like.
##
##   godot --path . --resolution 1600x900 --script res://tools/issue326_shots.gd

const SEED := 3260

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	scene.menus.close()
	var season := LeagueSeason.create("Results Continue", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	await _frames(2)
	var screen = league.screen
	# 1. Today's Fixtures before anything is played: the day's plan and its chips.
	_read("1 today's fixtures")
	await _shot("issue326_1_todays_fixtures")
	# 2. Continue on the hub: the day settles and its roundup opens.
	screen.click("continue")
	await _frames(2)
	print("PRESS hub continue -> mode=[%s] roundeday=[%s] clock=[%s]" % [
		str(screen.mode), _roundup_day(screen), _clock(season)])
	_read("2 the day's results")
	await _shot("issue326_2_results_roundup")
	var played: int = int(season.record.fixtures.played())
	var clock: String = _clock(season)
	# 3. Continue on Results: back to Today's Fixtures for the day the clock
	#    already stands on, with the next games still unwatched.
	screen.click("continue")
	await _frames(2)
	print("PRESS results continue -> mode=[%s] clock=[%s] played=%d" % [
		str(screen.mode), _clock(season), int(season.record.fixtures.played())])
	print("CHECK clock held=%s ledger held=%s" % [
		str(_clock(season) == clock), str(int(season.record.fixtures.played()) == played)])
	_read("3 today's fixtures, next day")
	await _shot("issue326_3_hub_next_day")
	# 4. The same next day at a handset's design height.
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	screen.refresh()
	await _shot("issue326_4_hub_next_day_phone")
	_read("4 today's fixtures, next day, phone")
	screen.close()
	print("EXIT season=", season.save.slug)
	quit()

## What the pose on screen really reads: its mode, the clock, and the hub plan
## with each row's chip, so the log can be tied to the picture.
func _read(label: String) -> void:
	var screen = league.screen
	var view: Dictionary = screen.current_view()
	var rows: Array = []
	for fx in view.get("plan", []):
		rows.append("%s v %s %s%s" % [str(fx.get("home_club_id", "")), str(fx.get("away_club_id", "")),
			str(fx.get("status", "")), " WATCH" if int(fx.get("watched", 0)) == 1 else " AUTO"])
	var back := {}
	for item in screen.buttons:
		if str(item["id"]) == "back":
			back = item
	print("POSE %s: mode=[%s] date=[%s] back_disabled=[%s] plan=[%s]" % [label,
		str(screen.mode), str(view.get("date", "")), str(bool(back.get("disabled", false))),
		", ".join(PackedStringArray(rows))])

func _clock(season) -> String:
	return str(season.state().get("date", ""))

func _roundup_day(screen) -> String:
	if (screen.roundup as Array).is_empty():
		return ""
	return str((screen.roundup[0].get("fixture", {}) as Dictionary).get("kickoff", ""))

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
