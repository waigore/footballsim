extends SceneTree


const SEED := 4050
const NAME := "Results Score Evidence"

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
	await _frames(2)
	league.screen.click("continue")
	await _frames(3)
	print("RESULTS mode=", league.screen.mode, " rows=", league.screen.roundup.size())
	await _scale(0.0)
	await _shot("issue-405-results-desktop")
	_report_cards("results-desktop", league.screen)
	await _scale(maxf(scene.get_viewport().get_visible_rect().size.y / 411.0, 1.0))
	await _shot("issue-405-results-phone")
	_report_cards("results-phone", league.screen)

	await _scale(0.0)
	league.screen.click("back")
	await _frames(3)
	var day := str(season.state()["date"])
	var held := str(league.screen.current_view()["plan"][0]["id"])
	league.screen.click("toggle:" + held)
	league.screen.click("continue")
	await _frames(2)
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")
	await _frames(2)
	print("WATCH date=", day, " fixture=", held, " paused=", scene.paused)
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
	await _frames(2)
	var key := InputEventKey.new()
	key.keycode = KEY_SPACE
	key.pressed = true
	scene._input(key)
	await _frames(3)
	print("HUB mode=", league.screen.mode, " holding=", league.is_holding(),
		" date=", str(season.state()["date"]))
	await _scale(0.0)
	await _shot("issue-405-hub-played-desktop")
	_report_cards("hub-played-desktop", league.screen)
	await _scale(maxf(scene.get_viewport().get_visible_rect().size.y / 411.0, 1.0))
	await _shot("issue-405-hub-played-phone")
	await _scale(0.0)
	LeagueDoors.open_calendar(league.screen)
	await _frames(3)
	await _shot("issue-405-calendar-desktop")
	_report_cards("calendar-desktop", league.screen)
	await _scale(maxf(scene.get_viewport().get_visible_rect().size.y / 411.0, 1.0))
	await _shot("issue-405-calendar-phone")
	print("EXIT ok")
	quit()


func _report_cards(pose: String, screen) -> void:
	var bold: Font = UiChrome.fonts()["bold"]
	var out: Array = ["vp=%s" % screen.design_vp()]
	for item in screen.buttons:
		if str(item.get("id")) in ["continue", "back"]:
			out.append("%s=%s" % [str(item["id"]), str(item["rect"])])
	var kinds := {}
	for item in screen.body.content:
		var kind := str(item.get("kind", ""))
		kinds[kind] = int(kinds.get(kind, 0)) + 1
		if not kind in ["result", "fixture", "row"]:
			continue
		var rect: Rect2 = item["rect"]
		var fx: Dictionary = item.get("report", {}).get("fixture", item.get("fixture", {}))
		if str(fx.get("status", "")) != "played":
			continue
		var score := "%d  –  %d" % [int(fx.get("home_goals", 0)), int(fx.get("away_goals", 0))]
		var w: float = UiChrome.text_width(bold, score, 13)
		var right: float = LeagueBlock.score_x(rect)
		var mid: float = LeagueBlock.score_x(rect, true)
		out.append("%s %s w=%.1f right_band=%.1f..%.1f mid=%.1f center=%.1f" % [
			kind, str(rect), w, right - w, right, mid, rect.get_center().x])
	out.append("kinds=%s" % str(kinds))
	print("CARDS ", pose, " ", " | ".join(PackedStringArray(out)))


func _scale(ui_scale: float) -> void:
	scene.dev.ui_scale = ui_scale
	scene._sync_overlay_scale()
	await _frames(3)
	var screen = scene.menus.league.screen
	if screen != null and screen.is_open():
		screen.refresh()
		await _frames(3)


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _shot(name: String) -> void:
	await _frames(5)
	RenderingServer.force_draw(false)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	img.save_png("res://shots/%s.png" % name)
	print("SHOT shots/%s.png %s hash=%d" % [name, str(img.get_size()), hash(img.get_data())])
