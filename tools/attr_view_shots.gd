extends SceneTree

## Evidence capture for the Simplified / Full attribute reading (#411).
##
## Opens the encyclopedia player page, the club squad table and an in-match
## player card, pressing every mode door, then shoots the desktop and the
## phone-landscape poses. Prints the grid geometry and the door rects beside the
## pixels so a reviewer can check the reading without counting pixels.
##
##   godot --path . --resolution 1600x900 --script res://tools/attr_view_shots.gd

var scene = null


func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _frames(2)
	Prefs.save_attrs("SIMPLIFIED")
	var host = scene.wiki_host
	host.open_page(WikiModel.PLAYER, "MUN-b-fernandes")
	await _frames(4)
	_report("player_simplified", host.screen)
	await _shot("attrs_player_simplified")

	host.screen.click("attrs:FULL")
	await _frames(4)
	_report("player_full", host.screen)
	await _shot("attrs_player_full")

	host.open_page(WikiModel.TEAM, "MUN")
	await _frames(5)
	_report("club_full", host.screen)
	await _shot("attrs_club_full")

	await _phone(host)
	_report("club_full_compact", host.screen)
	await _shot("attrs_club_full_compact")
	await _desktop()

	host.close()
	await _frames(2)
	scene._toggle_mode()
	scene.focus_id = 5
	scene.hud.slide = 1.0
	await _frames(12)
	_report_card("match_full_desktop")
	await _shot("attrs_match_full")

	Prefs.save_attrs("SIMPLIFIED")
	await _frames(4)
	_report_card("match_simple_desktop")
	await _shot("attrs_match_simplified")

	Prefs.save_attrs("FULL")
	await _phone(host)
	await _frames(8)
	_report_card("match_full_phone")
	await _shot("attrs_match_full_phone")
	host.open_page(WikiModel.PLAYER, "MUN-b-fernandes")
	await _frames(6)
	_report("player_full_phone", host.screen)
	await _shot("attrs_player_full_phone")
	host.close()
	await _frames(2)
	await _desktop()
	await _frames(6)
	_report_card("match_full_back_on_desktop")
	Prefs.save_attrs("SIMPLIFIED")
	print("EXIT")
	quit()


func _phone(host) -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 411.0, 1.0)
	scene._sync_overlay_scale()
	await _frames(4)
	if host.screen != null and host.screen.has_method("_refresh"):
		host.screen._refresh()
	await _frames(2)


func _desktop() -> void:
	scene.dev.ui_scale = 1.0
	scene._sync_overlay_scale()
	await _frames(4)


func _rows_of(screen) -> Array:
	var out: Array = []
	for row in screen.body._rows:
		var kind := str(row.get("k", ""))
		if kind == "gridrow":
			var groups: Array = row.get("groups", [])
			out.append("grid %d groups/%d cols %.0fx%.0f" % [groups.size(),
				int(row.get("cols", 0)), (row["rect"] as Rect2).size.x,
				(row["rect"] as Rect2).size.y])
		elif kind == "door":
			out.append("door '%s' %s" % [str(row.get("text", "")), str(row["rect"])])
		elif kind == "thead":
			out.append("thead %s" % str(row.get("cols", [])))
	return out


func _report(name: String, screen) -> void:
	print("ATTRS %s pref=%s vp=%s scroll=%.0f/%s %s" % [name, Prefs.load_attrs(),
		str(screen.design_vp()), screen.body.scroll, str(screen.body.max_scroll()),
		str(_rows_of(screen))])


func _report_card(name: String) -> void:
	var card = scene.hud.card
	var vp: Vector2 = scene.hud.design_vp()
	var p = card.player(scene.hud.engine, scene.hud.game)
	var cells := 0
	if p != null:
		cells = AttrView.flat(str(p.role), card._subs(p)).size()
	print("CARD %s mode=%s vp=%s rect=%s cells=%d door=%s" % [name, str(card.mode),
		str(vp), str(card.rect_for(vp)), cells, str(card.attrs_rect(vp))])


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
	print("SHOT shots/%s.png %s" % [name, str(img.get_size())])
