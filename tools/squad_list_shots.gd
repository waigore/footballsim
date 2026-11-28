extends SceneTree

const SEED := 4480042

var scene = null


func _initialize() -> void:
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await _frames(3)
	scene.menus.close()
	var season := LeagueSeason.create("UEFA List Evidence", "generated", "fixture_days", SEED,
		["PL"], false, [], true)
	if season == null:
		print("EXIT no season")
		quit()
		return
	var club := _english_entrant()
	var seller := _seller()
	_fill_list(club, seller)
	print("LIST %s used=%d/%d" % [club, SquadList.slots_used(club, "UCL"), SquadList.slots()])
	await _pose(Vector2(1600.0, 900.0), club, "issue448_uefa_list")
	var rider := _extra_adult(seller)
	if rider != "":
		PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [club, rider])
		SquadList.register(club, "UCL", rider, SquadList.INELIGIBLE, MarketDealRules.LIST)
		print("FORCED %s reads %s" % [rider, SquadList.state_of(rider, "UCL")])
		await _pose(Vector2(1600.0, 900.0), club, "issue448_ineligible")
	await _pose(Vector2(914.0, 411.0), club, "issue448_uefa_list_phone")
	print("EXIT done")
	quit()


func _pose(vp: Vector2, club: String, shot_name: String) -> void:
	root.size = Vector2i(roundi(vp.x), roundi(vp.y))
	await _frames(3)
	scene.dev.ui_scale = 0.0
	scene.hud_scale = 1.0
	scene.chrome_scale = 1.0
	scene.touch = vp.y < 620.0
	scene.menus.sync(Transform2D.IDENTITY, 1.0, scene.touch)
	if scene.wiki_host == null:
		print("SHOT %s skipped (no wiki host)" % shot_name)
		return
	scene.wiki_host.screen.touch = scene.touch
	scene.wiki_host.sync_scale()
	await _frames(3)
	scene.wiki_host.open_page(WikiModel.TEAM, club)
	await _frames(4)
	var screen = scene.wiki_host.screen
	var rows := 0
	var at := -1.0
	for row in screen.body.rows():
		if " LIST  ·  " in str(row.get("text", "")):
			rows += 1
			at = (row["rect"] as Rect2).position.y
	if at >= 0.0:
		screen.body.scroll_to(maxf(at - 24.0, 0.0))
		await _frames(3)
	print("POSE %s list_rows=%d at=%.1f scroll=%.1f" % [shot_name, rows, at,
		screen.body.scroll])
	await _capture(shot_name)
	scene.wiki_host.close()
	await _frames(2)


func _english_entrant() -> String:
	var rows := PLDatabase.rows(
		"SELECT cm.member_id FROM competition_member cm JOIN club c ON c.id = cm.member_id "
		+ "JOIN player p ON p.club_id = c.id "
		+ "WHERE cm.competition_id = 'UCL' AND cm.member_kind = 'club' AND c.stub = 0 "
		+ "AND c.competition_id = 'PL' GROUP BY cm.member_id "
		+ "ORDER BY COUNT(p.id) DESC, cm.member_id;")
	return str(rows[0]["member_id"]) if not rows.is_empty() else "ENG-MCI1"


func _seller() -> String:
	var rows := PLDatabase.rows(
		"SELECT c.id FROM club c WHERE c.competition_id = 'PL' AND c.stub = 0 "
		+ "AND NOT EXISTS (SELECT 1 FROM competition_member cm WHERE cm.member_kind = 'club' "
		+ "AND cm.member_id = c.id AND cm.competition_id IN ('UCL', 'UEL', 'UECL')) "
		+ "ORDER BY c.id;")
	return str(rows[0]["id"]) if not rows.is_empty() else "ENG-BRE1"


func _extra_adult(seller: String) -> String:
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id = ? AND age >= 21 ORDER BY ovr, id;", [seller]):
		return str(row["id"])
	return ""


func _fill_list(club: String, seller: String) -> void:
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id = ? AND age >= 21 ORDER BY id;", [club]):
		SquadList.register(club, "UCL", str(row["id"]), SquadList.REGISTERED)
	var used := SquadList.slots_used(club, "UCL")
	while used < SquadList.slots():
		var rider := _extra_adult(seller)
		if rider == "":
			return
		PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [club, rider])
		SquadList.register(club, "UCL", rider, SquadList.REGISTERED)
		used += 1


func _frames(count: int) -> void:
	for i in range(count):
		await process_frame


func _capture(shot_name: String) -> void:
	await _frames(3)
	var tex: ViewportTexture = scene.get_viewport().get_texture()
	if tex == null:
		print("SHOT %s skipped (no renderer)" % shot_name)
		return
	var img: Image = tex.get_image()
	if img == null:
		print("SHOT %s skipped (no image)" % shot_name)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % shot_name))
	print("SHOT %s %dx%d" % [shot_name, img.get_width(), img.get_height()])
