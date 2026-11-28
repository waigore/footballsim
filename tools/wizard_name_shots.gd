extends SceneTree

## Evidence capture for the New League name field opening blank (DR-20261128-11).
##
## Boots the real game scene, opens NEW LEAGUE and shoots the sheet with its
## hint, then with a name the player typed, then on a handset; finally creates a
## season from an untouched form and shoots the hub, which is the catalogue
## screen the diff maps to. Writes a PNG per pose into `res://shots/`.
##
##   godot --path . --resolution 1600x900 --script res://tools/wizard_name_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	league.open_wizard()
	await _refresh()
	_print_field("hint")
	await _shot("wiz_name_hint_desktop")
	var screen = league.screen
	for ch in ["w", "i", "n", "t", "e", "r", " ", "l", "e", "a", "g", "u", "e"]:
		screen.text_key(0, ch.unicode_at(0))
	await _refresh()
	_print_field("typed")
	await _shot("wiz_name_typed_desktop")
	screen.click("name")
	await _refresh()
	screen.wizard["name"] = ""
	await _refresh()
	await _phone()
	_print_field("phone")
	await _shot("wiz_name_hint_phone")
	await _desktop()
	screen.wizard["name"] = ""
	screen.focus.blur()
	await _refresh()
	screen.click("create")
	await _frames(4)
	var season: LeagueSeason = LeagueSeason.active
	if season != null:
		league.show_season(season)
	await _refresh()
	print("WIZARD create name=[%s] slug=[%s]" % [
		"" if season == null else str(season.save.name()),
		"" if season == null else str(season.save.slug)])
	await _shot("league_hub_desktop")
	print("WIZARD done vp=%s" % scene.get_viewport().get_visible_rect().size)
	quit()

func _print_field(label: String) -> void:
	var screen = scene.menus.league.screen
	var rect := LeagueFieldFocus.field_rect(screen, LeagueFieldFocus.WIZARD)
	var typed := str(screen.wizard.get("name", ""))
	print("WIZARD %s vp=%s field=%.0fx%.0f@%.0f,%.0f held=[%s] saves_as=[%s]" % [label,
		str(screen.design_vp()), rect.size.x, rect.size.y, rect.position.x, rect.position.y,
		typed, LeagueStartSheet.save_name(typed)])

func _phone() -> void:
	var vp: Vector2 = scene.get_viewport().get_visible_rect().size
	scene.dev.ui_scale = maxf(vp.y / 411.0, 1.0)
	scene.touch = true
	scene._sync_overlay_scale()
	await _refresh()

func _desktop() -> void:
	scene.dev.ui_scale = 0.0
	scene.touch = false
	scene._sync_overlay_scale()
	await _refresh()

func _refresh() -> void:
	await _frames(2)
	var league: LeagueHost = scene.menus.league
	if league.screen != null and league.screen.is_open():
		league.sync(Transform2D.IDENTITY.scaled(Vector2(scene.chrome_scale, scene.chrome_scale)),
			scene.chrome_scale, scene.touch)
		league.screen.refresh()
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
