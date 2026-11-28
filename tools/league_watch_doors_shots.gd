extends SceneTree

## Evidence capture for issue #418: a watched league fixture offers no Change
## teams and no Restart on any entry point, while a single match keeps both.
##
## Boots the real game scene and reads one match twice. First a single match from
## the picker: the strip's `RESTART` answers, the fixture card's `CHANGE TEAMS`
## answers, `R` reseeds and `T` opens the picker. Then a generated season with one
## fixture marked to watch: the same two doors are painted dead on the desktop and
## in a handset space (where the strip grows a `TEAMS` door), `R` and `T` change
## nothing, and `MENU` still hands the season the match, which finishes at speed
## and is saved. Writes a PNG per pose into `res://shots/` and prints every
## reading, so the pictures and the numbers can be checked together. Run it on a
## display; a headless run has no frame to read back.
##
##   godot --path . --script res://tools/league_watch_doors_shots.gd

## The fixture card's CHANGE TEAMS rect as `HudTopBand.meta` lays it: the panel
## sits at (24, 24) and the door 12 units in and 68 down, 262 x 20 units.
const CARD_DOOR := Rect2(36.0, 92.0, 262.0, 20.0)

const DESKTOP := Vector2i(1600, 900)

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "LIV")
	_kick_briefing()
	await _frames(2)
	scene.paused = true
	scene.hud.queue_redraw()
	await _frames(2)
	print("SINGLE viewer=", scene.home_id, " v ", scene.away_id, " friendly=", scene.billing.friendly)
	await _probe("single match")
	await _shot("issue-418-single-match-desktop")
	scene.hud.set_hud_visible(false, true)
	scene.hud.queue_redraw()
	await _frames(3)
	await _shot("issue-418-match-hud-hidden")
	scene.hud.set_hud_visible(true, true)
	scene.hud.queue_redraw()
	await _frames(3)

	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Doors Evidence", "generated", "fixture_days", 418)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	league.show_season(season)
	var held := str(league.screen.current_view()["plan"][0]["id"])
	league.screen.click("toggle:" + held)
	league.screen.click("continue")
	_kick_briefing()
	await _frames(2)
	scene.paused = true
	scene.hud.queue_redraw()
	await _frames(2)
	print("WATCH fixture=", held, " viewer=", scene.home_id, " v ", scene.away_id,
		" watching=", season.watching_fixture, " friendly=", scene.billing.friendly)
	await _probe("league watch")
	await _shot("issue-418-league-watch-desktop")

	scene.dev.ui_scale = 2.2
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	root.size = Vector2i(1826, 822)
	DisplayServer.window_set_size(Vector2i(1826, 822))
	scene._sync_overlay_scale()
	scene.hud.queue_redraw()
	await _frames(3)
	await _probe("league watch (phone)")
	await _shot("issue-418-league-watch-phone")
	scene.dev.ui_scale = 0.0
	scene.touch = false
	root.size = DESKTOP
	DisplayServer.window_set_size(DESKTOP)
	scene._sync_overlay_scale()
	await _frames(3)

	scene.menus.open_menu()
	var guard := 0
	while league.watch.settling() and guard < 40000:
		league.watch.tick()
		guard += 1
	print("LEFT settling=", league.watch.settling(), " slices=", guard,
		" played=", str(season.report(held).get("played", false)),
		" shell=", str(scene.menus.shell.visible), " season_open=", str(league.is_open()))
	print("EXIT ok fixture=", held)
	quit()

## Read what the two doors do, then put the scene back the way it was so the
## picture matches the numbers.
func _probe(label: String) -> void:
	await _frames(1)
	scene.hud.queue_redraw()
	await _frames(1)
	var ids: Array = []
	for b in scene.hud.buttons:
		ids.append(str(b["id"]))
	var card_drawn: bool = not scene.hud.touch and not HudLayout.is_compact(scene.hud.design_vp())
	var card_answers: String = scene.hud.button_at(CARD_DOOR.get_center()) if card_drawn else ""
	var seed_before: int = scene.seeded
	var clock_before: float = scene.engine.clock
	var phase_before: String = str(scene.engine.phase)
	_key(KEY_R)
	var reseeded: bool = scene.seeded != seed_before or scene.engine.clock < clock_before
	_key(KEY_T)
	var picker: bool = scene.select_open
	print("%s: doors=%s card=T@%s card_answers=%s R_reseeded=%s T_picker=%s" % [
		label, str(ids), str(CARD_DOOR),
		card_answers if card_answers != "" else ("not on this pose" if not card_drawn else "none"),
		str(reseeded), str(picker)])
	if picker:
		_key(KEY_ESCAPE)
	if reseeded:
		scene.engine.phase = phase_before
		scene.hud.queue_redraw()
		await _frames(1)

## Every watched match opens the pre-match briefing first (#157): kick it off so
## the pose this tool reads is the match, not the briefing.
func _kick_briefing() -> void:
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")

func _key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	scene._input(ev)

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

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
	print("SHOT ", name, " ", img.get_size())
