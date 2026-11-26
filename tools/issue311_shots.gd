extends SceneTree

## Evidence capture for #311: at a watched league fixture's whistle the control
## bar used to advertise a gold `PLAY AGAIN` and a live `R`, while the held FULL
## TIME card swallowed every press and every key.
##
## Boots the real game scene, creates a generated season, marks one fixture to
## watch, plays it to full time and shoots the held card at desktop and phone
## metrics; then a friendly at the same whistle, where `PLAY AGAIN` is real, so
## the two strips can be compared side by side.
##
## It prints the doors the overlay answered with (and the key each printed) at
## every pose, plus what `R` did, so the capture is read back rather than
## eyeballed. Run it on a display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/issue311_shots.gd

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
	var season := LeagueSeason.create("Held Whistle 311", "generated", "fixture_days", 2026)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var fixture := str(league.screen.current_view()["plan"][0]["id"])
	league.screen.click("toggle:" + fixture)
	league.screen.click("continue")
	_kick_briefing()
	await _frames(2)
	# Park the match a second short of full time and let the engine whistle.
	scene.engine.half = 2
	scene.engine.clock = 5399.0
	scene.engine.added[1] = 0.0
	var guard := 0
	while scene.engine.phase != "full_time" and guard < 400:
		scene._advance_ticks(600)
		scene._post_tick()
		if scene.engine.phase == "half_time":
			scene.engine.begin_second_half()
		guard += 1
	scene._process(0.016)
	await _frames(3)
	print("HELD phase=", scene.engine.phase, " holding=", league.is_holding(),
		" result_hold=", scene.result_hold, " touch=", scene.hud.touch)
	await _shot("issue311_held_whistle_desktop")
	_print_doors("held desktop")
	_read_r()
	# The phone design space: the same held card, the same dead strip.
	scene.dev.ui_scale = 2.2
	scene._sync_overlay_scale()
	scene.hud.queue_redraw()
	await _shot("issue311_held_whistle_phone")
	_print_doors("held phone")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	# The contrast: a friendly at the same whistle, where PLAY AGAIN is real.
	league.close()
	scene.new_match(311)
	scene.result_hold = false
	scene.menus.close()
	scene.hud_layer.visible = true
	scene.hud.set_hud_visible(true, true)
	scene.paused = false
	scene.engine.clock = 90.0 * 60.0
	scene.engine.half = 2
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.engine.goal_sheet = [
		{"team": 0, "minute": 22, "scorer": "P. Foden", "own_goal": false},
		{"team": 1, "minute": 57, "scorer": "B. Šeško", "own_goal": false},
		{"team": 0, "minute": 78, "scorer": "E. Haaland", "own_goal": false},
	]
	scene.engine.phase = "full_time"
	scene.hud.ticker.hold = 0.0
	scene.hud.queue_redraw()
	await _frames(3)
	print("FRIENDLY phase=", scene.engine.phase, " holding=false result_hold=", scene.result_hold)
	await _shot("issue311_friendly_whistle_desktop")
	_print_doors("friendly desktop")
	quit()

## Every door the overlay answered with, with the key each printed. An empty
## bracket is the fix: nothing on the strip can answer while the card holds.
func _print_doors(label: String) -> void:
	var out: Array = []
	for b in scene.hud.buttons:
		var hint := str(b.get("hint", ""))
		out.append(str(b["id"]) if hint == "" else "%s/%s" % [str(b["id"]), hint])
	print("DOORS %s = [%s]" % [label, ", ".join(PackedStringArray(out))])

## `R` is the replay key the gold door used to advertise: it must change nothing
## while the season holds the result, and the season must still be holding after.
func _read_r() -> void:
	var before_seed: int = scene.seeded
	var before_clock: float = scene.engine.clock
	var key := InputEventKey.new()
	key.keycode = KEY_R
	key.pressed = true
	scene._input(key)
	await _frames(2)
	print("R held=", scene.result_hold, " seed_changed=", scene.seeded != before_seed,
		" clock_changed=", not is_equal_approx(scene.engine.clock, before_clock))

func _kick_briefing() -> void:
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")

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
