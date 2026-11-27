extends SceneTree

## Evidence capture for DR-20261127-10: a player page lists his season match by
## match. Boots the real game, builds a generated season, plays three rounds, opens
## the leading scorer's page over the season, and writes a desktop and a handheld
## pose into `res://shots/`. Run it on a display; a headless run has no frame.
##
##   godot --path . --script res://tools/player_log_shots.gd

const SEED := 2031

var scene = null

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var league: LeagueHost = scene.menus.league
	var season := LeagueSeason.create("Player Log Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	for i in range(3):
		season.advance()
	var scorer: Dictionary = season.record.report.top_scorers(1)[0]
	league.show_season(season)
	await _frames(2)
	scene.wiki_host.open_page_over_league(WikiModel.PLAYER, str(scorer["player_id"]))
	await _frames(2)
	var body = scene.wiki_host.screen.body
	body.scroll_to(100000.0)
	var vp: Vector2 = scene.get_viewport_rect().size
	await _shot("player_log")
	print("LOG player=", scorer["name"], " rows=", _log_rows(body).size(),
		" window=", int(vp.x), "x", int(vp.y))
	scene.dev.ui_scale = 0.0
	scene._sync_overlay_scale()
	print("EXIT season=", season.save.slug)
	quit()

func _log_rows(body) -> Array:
	var out: Array = []
	var inside := false
	for row in body.rows():
		var kind := str(row.get("k", ""))
		if kind == "thead":
			inside = (row.get("cols", []) as Array).has("HIS PART")
			continue
		if inside and kind == "trow":
			out.append(row)
	return out

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _shot(name: String) -> void:
	await _frames(6)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var pose := "desktop" if img.get_width() >= 1400 else "phone"
	img.save_png(ProjectSettings.globalize_path("res://shots/%s_%s.png" % [name, pose]))
	print("SHOT %s_%s %dx%d" % [name, pose, img.get_width(), img.get_height()])
