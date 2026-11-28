extends SceneTree

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	await _desktop()
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Result Chips Evidence", "generated", "fixture_days", 2026,
		["PL", "LL"])
	if season == null:
		print("CHIPS no season")
		quit()
		return
	league.show_season(season)
	await _frames(4)
	league.screen.refresh()
	await _frames(2)
	league.screen.click("continue")
	await _frames(4)
	await _shot("result_chips_mixed_desktop")
	_print_chips("mixed desktop")
	league.screen.body.scroll_to(420.0)
	await _frames(3)
	await _shot("result_chips_scrolled_desktop")
	league.screen.body.scroll_to(0.0)
	await _frames(2)
	league.screen.click("resultleague:LL")
	await _frames(3)
	await _shot("result_chips_ll_desktop")
	_print_chips("ll desktop")
	league.screen.click("resultleague:LL")
	await _frames(2)
	season.set_interest("ENG-ARS1", true)
	league.screen.refresh()
	await _frames(3)
	league.screen.click("resultinterest")
	await _frames(3)
	await _shot("result_chips_interest_desktop")
	_print_chips("interest desktop")
	league.screen.click("resultinterest")
	season.set_interest("ENG-ARS1", false)
	league.screen.refresh()
	await _frames(2)
	await _phone()
	league.screen.refresh()
	await _frames(3)
	await _shot("result_chips_mixed_phone")
	_print_chips("mixed phone")
	league.detach_season()
	league.close()
	await _frames(2)
	quit()

func _print_chips(label: String) -> void:
	var screen = scene.menus.league.screen
	var vp: Vector2 = screen.design_vp()
	var chips: Array = []
	var rows := 0
	for b in screen.buttons:
		var id := str(b["id"])
		if id.begins_with("resultleague:") or id == "resultinterest":
			var r: Rect2 = b["rect"]
			chips.append("%s=%.0fx%.0f@%.0f,%.0f" % [id, r.size.x, r.size.y, r.position.x,
				r.position.y])
		elif id.begins_with("match:"):
			rows += 1
	print("CHIPS %s vp=%s touch=%s rows=%d %s" % [label, str(vp), str(screen.touch), rows,
		" ".join(PackedStringArray(chips))])

func _desktop() -> void:
	scene.dev.ui_scale = 1.0
	scene._sync_overlay_scale()
	await _frames(2)

func _phone() -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 411.0, 1.0)
	scene._sync_overlay_scale()
	await _frames(2)

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
