extends SceneTree

## Evidence capture for issue #200: the fixture picker used to paint the venue
## name centred in the gap between the two club cards with no width limit, so a
## normal ground (`OLD TRAFFORD`) started over the left card and ended over the
## right card — and the two inner arrows filled most of that gap anyway.
##
## The caption now rides under the inner arrows and is fitted to the column it
## sits in, so it never crosses the cards or the doors. Boots the real game
## scene and shoots:
##
##   * the desktop pose (1600x900),
##   * a 411 dp handset in landscape (2400x1080 at 420 dpi),
##   * a 360 dp handset in landscape (1280x720 at 320 dpi),
##   * the widest ground in the seed, shortened to the handset column.
##
## Each pose prints the design viewport, the column, the room and the caption it
## drew, then writes a PNG into `res://shots/`. Run it on a display; a headless
## run has no frame to read back.
##
##   xvfb-run -a godot --path . --resolution 2400x1080 --script res://tools/issue200_shots.gd

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	await _pose("issue200_desktop", 0.0, "MUN", "MCI")
	await _pose("issue200_phone_411", HudLayout.scale_for(411.0), "MUN", "MCI")
	await _pose("issue200_phone_360", HudLayout.scale_for(360.0), "MUN", "MCI")
	# The widest ground in the seed: on a handset its column cannot hold the
	# whole name, so the caption is shortened rather than painted over the cards.
	await _pose("issue200_phone_360_long", HudLayout.scale_for(360.0), _long_venue_club(), "MCI")
	quit()

## The club whose ground name is widest at the caption's type size.
func _long_venue_club() -> String:
	var med: FontFile = load("res://fonts/BarlowCondensed-Medium.ttf")
	var best := "MUN"
	var widest := 0.0
	for id in TeamData.team_ids():
		var venue := str(TeamData.get_team(id).get("stadium", "")).to_upper()
		var w: float = med.get_string_size(venue, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x
		if w > widest:
			widest = w
			best = str(id)
	return best

func _pose(name: String, scale: float, home: String, away: String) -> void:
	scene.dev.ui_scale = scale
	scene._sync_overlay_scale()
	scene.open_select(true)
	scene.selector.setup(home, away)
	scene.selector.queue_redraw()
	await _frames(5)
	var sel = scene.selector
	var vp: Vector2 = sel.design_vp()
	var gap: float = clampf(vp.x * 0.14, 130.0, 220.0)
	var room: float = gap - 24.0
	var venue := str(TeamData.get_team(home).get("stadium", "")).to_upper()
	var shown: String = LeagueColumns.fit_caption(venue, sel.f_med, 10, room)
	print("%s: vp=%s scale=%.2f gap=%.1f room=%.1f venue=%s shown=%s w=%.1f" % [
		name, vp, sel.ui_scale, gap, room, venue, shown,
		sel.f_med.get_string_size(shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x])
	await _shot(name)
	scene.fixture.close()

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
