extends SceneTree

## Evidence capture for the Android touch fixes (#265, #266, #273, #274).
##
## Boots the real game scene and shoots, at the phone design space:
##
##   * the match bar while a replay view sims — the speed door's caption and the
##     state line above the bar (#265),
##   * the fixture picker's header band — the league chips and the heading (#266),
##   * the New League form after a season left its drawer out (#273),
##   * the encyclopedia's league table rows (#274).
##
## Each pose prints the geometry it shot, so the numbers are checked as well as
## the pixels. Writes a PNG per pose into `res://shots/`. Run it on a display.
##
##   godot --path . --resolution 1600x900 --script res://tools/android_fix_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	# ---- #265: the simming match bar.
	scene.menus.close()
	scene.hud_layer.visible = true
	scene._on_fixture_confirmed("MUN", "MCI")
	if scene.prematch != null and scene.prematch.is_open():
		scene.prematch.screen.click("kick")
		await _frames(2)
	scene.paused = false
	scene.set_process(false)
	scene.engine.clock = 63.0 * 60.0
	scene.engine.score[0] = 2
	scene.engine.score[1] = 1
	scene.view.set_mode("highlights")
	scene.fast_mode = true
	scene.hud.set_hud_visible(true, true)
	await _phone(1.0)
	scene.hud.queue_redraw()
	await _shot("android265_simming_door")
	_print_door("highlights simming")
	scene.view.set_mode("full")
	scene.fast_mode = false
	scene.speed = 4.0
	scene.hud.queue_redraw()
	await _shot("android265_full_match_door")
	_print_door("full match 4x")
	# ---- #266: the picker's header band. The picker is its own sheet.
	await _desktop()
	scene.open_select(true)
	await _frames(2)
	await _phone(1.0)
	await _shot("android266_picker_header")
	_print_picker()
	await _desktop()
	scene.fixture.close()
	# ---- #273: the New League form, reached from a season whose drawer was out.
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Android Fix Evidence", "generated", "fixture_days", 2026)
	if season != null:
		league.show_season(season)
		await _frames(2)
		await _phone(1.0)
		league.screen.panel.open()
		league.screen.panel.settle()
		league.screen.refresh()
		await _frames(2)
		await _shot("android273_hub_drawer_out")
		print("HUB pose=%s drawer_open=%s" % [str(league.screen.overlay.active_pose),
			str(league.screen.panel.is_open())])
		scene.menus.open_menu()
		await _frames(2)
		_press_menu("new_league")
		await _frames(3)
		await _shot("android273_new_league_form")
		_print_plate()
		league.detach_season()
		league.close()
		await _frames(2)
	# ---- #274: the encyclopedia's league table, on the same phone space.
	scene.menus.close()
	await _frames(2)
	scene.wiki_host.open_page(WikiModel.LEAGUE, "")
	await _frames(3)
	await _shot("android274_wiki_rows")
	_print_wiki()
	scene.wiki_host.close()
	await _frames(2)
	print("EXIT mode=%s touch=%s scale=%.2f" % [scene.mode, str(scene.touch), scene.hud_scale])
	quit()

## The handset design space: the overlay layer is scaled up, so every sheet lays
## out in the smaller space a thumb actually sees.
func _phone(extra_scale: float) -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 411.0, 1.0) * extra_scale
	scene._sync_overlay_scale()
	await _frames(2)

func _desktop() -> void:
	scene.dev.ui_scale = 1.0
	scene._sync_overlay_scale()
	await _frames(2)

func _press_menu(id: String) -> void:
	var shell = scene.menus.shell
	var rect := Rect2()
	for b in MenuScreen.door_rects(shell.design_vp(), bool(shell.has_match)):
		if str(b["id"]) == id:
			rect = b["rect"]
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = rect.get_center() * shell.ui_scale
		scene._input(ev)

func _print_door(label: String) -> void:
	var p := HudPaint.new(scene.hud.chrome, scene.hud.design_vp())
	var door := ""
	var hint := ""
	var door_rect := Rect2()
	var bar := HudLayout.controls_rect(p.vp, scene.touch)
	var bw: float = HudLayout.control_width(p.vp, scene.touch)
	var gap: float = HudLayout.CONTROL_GAP
	var per: int = HudLayout.controls_per_row(p.vp, scene.touch)
	var specs: Array = scene.hud.controls_band.control_specs(p, scene, scene.touch)
	for i in range(specs.size()):
		var r := Rect2(bar.position.x + float(i % per) * (bw + gap),
			bar.position.y + float(i / per) * (HudLayout.CONTROL_H + gap), bw, HudLayout.CONTROL_H)
		if str(specs[i][0]) == "speed":
			door = str(specs[i][1])
			hint = str(specs[i][2])
			door_rect = r
	var line: String = scene.hud.roster_band.state_label(scene, scene.hud.controls_band.speed_label(scene))
	print("DOOR %s: door=%s hint='%s' status=%s rect=%s vp=%s" % [label, door, hint, line,
		door_rect, p.vp])

func _print_picker() -> void:
	var picker = scene.selector
	var vp: Vector2 = picker.design_vp()
	var head: Dictionary = LeagueChrome.picker_header(vp)
	var band: Rect2 = LeagueChrome.picker_chips_band(vp)
	print("PICKER vp=%s compact=%s heading=%s chips=%s rule_y=%.1f" % [vp, bool(head["compact"]),
		str(head["title"]), band, float(head["rule_y"])])
	var chips := 0
	for b in picker.buttons:
		if str(b["id"]).begins_with("league:"):
			chips += 1
	print("PICKER chips=%d" % chips)

func _print_plate() -> void:
	var screen = scene.menus.league.screen
	var vp: Vector2 = screen.design_vp()
	var door: Rect2 = screen.panel.tab_rect(vp)
	var covered: Array = []
	for b in screen.buttons:
		if (b["rect"] as Rect2).intersects(door):
			covered.append(str(b["id"]))
	print("PLATE vp=%s mode=%s pose='%s' drawer_open=%s plate=%s answers='%s' controls_under=%s" % [
		vp, screen.mode, str(screen.overlay.active_pose), str(screen.panel.is_open()), door,
		screen.panel.hit(door.get_center(), vp), covered])

func _print_wiki() -> void:
	var body = scene.wiki_host.screen.body
	var rows: Array = []
	for row in body.rows():
		if str(row["k"]) == "trow":
			rows.append(row["rect"])
	if rows.size() < 2:
		print("WIKI no rows")
		return
	print("WIKI vp=%s rows=%d pitch=%.1f row_h=%.1f touch=%s" % [body.size, rows.size(),
		(rows[1] as Rect2).position.y - (rows[0] as Rect2).position.y,
		(rows[0] as Rect2).size.y, str(body.touch)])
	var r: Rect2 = rows[0]
	var hit: Dictionary = body.hit(Vector2(60.0, r.position.y + r.size.y * 0.5))
	print("WIKI first row answers=%s" % str(hit.get("id", "")))

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
	img.save_png("res://shots/%s.png" % name)
	print("SHOT shots/%s.png %s" % [name, img.get_size()])
