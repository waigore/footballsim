extends SceneTree

## Evidence capture for issue #284: Today's Fixtures lost CONTINUE.
##
## The body that scrolls a league sheet clips its own `_draw`, and Godot clips
## every command a Control draws for itself — not just its children. The doors a
## sheet pins in screen space (BACK and CONTINUE in the header lane, the table's
## reading doors under the bottom bar) sit outside the body's band, so they were
## painted and then thrown away. BACK still appeared because `LeagueExtra.header`
## paints one on the screen itself; CONTINUE had no twin.
##
## This walks the poses the issue names on a desktop window and at handset scale,
## prints each pose's door rect against the body's band, and writes a PNG per pose
## into `res://shots/`.
##
##   godot --path . --resolution 1600x900 --script res://tools/issue284_shots.gd

const SEED := 2840

var scene = null
var league: LeagueHost = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	league = scene.menus.league
	scene.menus.close()
	var season := LeagueSeason.create("Pinned Doors", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	# One played matchday: the roundup pose carries the hub's CONTINUE too.
	season.advance()
	var played: Array = season.advance().get("played", [])
	league.show_season(season)
	await _shot("issue284_hub")

	league.screen.click("table")
	await _shot("issue284_table")
	league.screen.click("back")

	if not played.is_empty():
		var reports: Array = []
		for entry in played:
			reports.append(season.report(str((entry.get("fixture", {}) as Dictionary).get("id", ""))))
		league.screen.show_roundup(reports)
		await _shot("issue284_roundup")
		league.screen.click("back")

	# The same two poses at 411 dp, which is a handset's design height.
	scene.dev.ui_scale = scene.get_viewport_rect().size.y / 411.0
	scene._sync_overlay_scale()
	league.screen.refresh()
	await _shot("issue284_hub_phone")
	league.screen.click("table")
	await _shot("issue284_table_phone")
	league.screen.click("back")
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	print("EXIT season=", season.save.slug)
	quit()

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
	# Force the draw stage before reading back: a queued redraw the draw stage
	# never reached saves the previous pose.
	RenderingServer.force_draw(false)
	_report(name)
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
	print("SHOT %s %dx%d hash=%d" % [name, img.get_width(), img.get_height(), hash(img.get_data())])

## The band the body clips against, and where each header/bar door was laid:
## a door whose rect lies outside the band is a door the clip can eat.
func _report(name: String) -> void:
	if league == null or league.screen == null or not scene.menus.league_active():
		return
	var screen: LeagueScreen = league.screen
	var vp: Vector2 = screen.design_vp()
	var body: LeagueBody = screen.body
	var band := Rect2(body.position, body.size)
	var out: Array = []
	out.append("mode=" + str(screen.mode))
	out.append("vp=%s" % str(vp))
	out.append("band=%s" % str(band))
	var pinned: Array = []
	for item in screen.buttons:
		var id := str(item["id"])
		if str(item["id"]) in ["back", "continue"] or id.begins_with("tbl:mode:"):
			var rect: Rect2 = item["rect"]
			var covered := band.has_point(rect.position) and band.has_point(rect.end - Vector2(0.5, 0.5))
			out.append("%s=%s%s" % [id, str(rect), "" if bool(item.get("pinned", false)) else " (scrolls)"])
			if bool(item.get("pinned", false)):
				pinned.append("%s:%s" % [id, "inside" if covered else "OUTSIDE the clip"])
	print("CHROME ", name, " ", " ".join(PackedStringArray(out)))
	print("CLIP ", name, " ", " ".join(PackedStringArray(pinned)))
