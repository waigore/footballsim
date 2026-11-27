extends SceneTree

## Evidence capture for issue #352 / #353 / #354: club and player encyclopedia
## pages read the open season's absentees with a calendar return day.
##
## Boots the real game scene, opens a live season, puts one body on the injury
## list and one on a two-match ban through the sim's own entry points, then
## shoots the club squad and the player page on a phone and on a desktop window.
## It also prints the status strings the pages build and the XI the injured body
## is missing from.
##
##   xvfb-run -a godot --path . --script res://tools/issue352_shots.gd

var scene = null
var club := "MUN"
var hurt: Dictionary = {}
var banned: Dictionary = {}

func _initialize() -> void:
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	var season := LeagueSeason.create("Absence Evidence", "generated", "fixture_days", 352)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	season.advance()
	scene.menus.league.show_season(season)
	var team := TeamData.get_team(club)
	hurt = team["starters"][0]
	banned = team["starters"][1]
	var day := str(season.save.current_date())
	SeasonAvailability.injure(str(hurt["id"]), club, day, "muscle", 24, 1.0)
	SeasonAvailability.suspend(str(banned["id"]), club, 2, "red", day)
	_report(season)
	await _design(Vector2(1096.0, 493.0), true)
	scene.wiki_host.open_page_over_league(WikiModel.TEAM, club)
	await _frames(4)
	_scroll_to_player(str(hurt["name"]))
	await _frames(4)
	await _capture("issue352_phone_club_squad")
	scene.wiki_host.screen.open(WikiModel.PLAYER, str(hurt["id"]))
	await _frames(4)
	await _capture("issue352_phone_player_injured")
	scene.wiki_host.screen.open(WikiModel.PLAYER, str(banned["id"]))
	await _frames(4)
	await _capture("issue352_phone_player_banned")
	await _design(Vector2(1600.0, 900.0), false)
	scene.wiki_host.screen.open(WikiModel.TEAM, club)
	await _frames(4)
	_scroll_to_player(str(hurt["name"]))
	await _frames(4)
	await _capture("issue352_desktop_club_squad")
	scene.wiki_host.screen.open(WikiModel.PLAYER, str(banned["id"]))
	await _frames(4)
	await _capture("issue352_desktop_player_banned")
	scene.wiki_host.screen.open(WikiModel.PLAYER, str(team["starters"][2]["id"]))
	await _frames(4)
	await _capture("issue352_desktop_player_fit")
	print("EXIT done")
	quit()

func _report(season) -> void:
	print("SEASON day=%s club=%s" % [str(season.save.current_date()), club])
	for id in [str(hurt["id"]), str(banned["id"])]:
		print("STATUS %s -> \"%s\"" % [id, WikiAbsence.status_of(club, id)])
	var rows := WikiAbsence.statuses(club)
	print("STATUSES out=%d off=%s" % [rows.size(), str(rows)])
	var xi := StrongestXI.pick(TeamData.get_team(club))
	var picked := false
	for p in xi:
		if str(p["id"]) == str(hurt["id"]) or str(p["id"]) == str(banned["id"]):
			picked = true
	print("XI size=%d out_picked=%s" % [xi.size(), str(picked)])
	for fx in PLRepository.shared().upcoming(club, 3):
		print("NEXT %s" % str(fx["kickoff"]))

func _scroll_to_player(name: String) -> void:
	var body = scene.wiki_host.screen.body
	if body == null:
		return
	for row in body.rows():
		if str(row.get("k", "")) != "trow":
			continue
		var cells: Array = row.get("cells", [])
		if cells.size() >= 2 and str(cells[1]) == name:
			var rect: Rect2 = row["rect"]
			body.scroll_to(maxf(0.0, rect.position.y - 120.0))
			return

func _design(vp: Vector2, touch: bool) -> void:
	var scale: float = scene.get_viewport().get_visible_rect().size.x / vp.x
	scene.dev.ui_scale = scale
	scene._sync_overlay_scale()
	scene.touch = touch
	if scene.wiki_host != null:
		scene.wiki_host.screen.touch = touch
		scene.wiki_host.sync_scale()
	await _frames(4)
	print("DESIGN %s touch %s" % [str(vp), str(touch)])

func _frames(count: int) -> void:
	for i in range(count):
		await process_frame

func _capture(name: String) -> void:
	await _frames(3)
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
