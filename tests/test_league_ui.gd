extends GdToolsTest

## The league surfaces driven through the real scene: menu doors, the setup
## wizard, the planner and Continue loop, a watched fixture, the table, the
## calendar, reports and the podium.

const SAVE_DIR := "user://saves_test_ui_issue58"
const CACHE_DIR := "user://cache_test_ui_issue58"
const PREFS := "user://test_league_ui_issue58.cfg"

var game = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	game.menus.open_menu()

func after_all() -> void:
	if game != null:
		if game.menus.league != null:
			game.menus.league.close()
		game.queue_free()
	LeagueSeason.active = null
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func vp() -> Vector2:
	return game.menus.shell.design_vp()

func door(id: String) -> Rect2:
	for b in MenuScreen.door_rects(vp(), bool(game.menus.shell.has_match)):
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func press(p: Vector2) -> void:
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = p * game.menus.shell.ui_scale
	game._input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = p * game.menus.shell.ui_scale
	game._input(up)

func screen():
	return game.menus.league.screen

func press_id(id: String) -> void:
	for item in screen().buttons:
		if str(item["id"]) == id:
			press((item["rect"] as Rect2).get_center())
			return
	assert_true(false, "no button %s on screen %s" % [id, screen().mode])

# ------------------------------------------------------------------ menu ---

func test_the_menu_offers_new_and_load_league() -> void:
	var ids: Array = []
	for b in MenuScreen.door_rects(vp(), false):
		ids.append(str(b["id"]))
	assert_true(ids.has("new_league"), "the menu has no New League door")
	assert_true(ids.has("load_league"), "the menu has no Load League door")
	assert_eq(ids.size(), 5, "the menu door count moved")

func test_new_league_opens_the_wizard_and_takes_the_setup() -> void:
	game.menus.open_menu()
	press(door("new_league").get_center())
	assert_true(game.menus.league_active(), "New League did not open the league surface")
	assert_eq(screen().mode, LeagueScreen.MODE_WIZARD, "the wizard did not open")
	press_id("mode:real")
	assert_eq(str(screen().wizard["calendar_mode"]), "real", "the fixture mode was not taken")
	press_id("adv:every_day")
	assert_eq(str(screen().wizard["advance_mode"]), "every_day", "the advance mode was not taken")
	for i in range(12):
		screen().key(KEY_BACKSPACE)
	screen().key(KEY_A)
	screen().key(KEY_B)
	assert_eq(str(screen().wizard["name"]), "AB", "typing did not reach the name")
	press_id("create")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Create did not land on the hub")
	assert_not_null(LeagueSeason.active, "no season is active")
	assert_eq(str(LeagueSeason.active.state()["advance_mode"]), "every_day", "the save did not keep its advance mode")

func test_the_hub_plans_and_toggles_a_fixture() -> void:
	var plan: Array = screen().current_view()["plan"]
	assert_gte(plan.size(), 1, "the hub does not list the matchday")
	var fixture_id := str(plan[0]["id"])
	var toggle_id := "toggle:" + fixture_id
	press_id(toggle_id)
	assert_eq(screen().current_view()["plan"].size(), plan.size(), "the planner lost a row")
	var after: Array = screen().current_view()["plan"]
	assert_eq(int(after[0]["watched"]), 1, "the watch flag did not stick")
	press_id(toggle_id)
	assert_eq(int(screen().current_view()["plan"][0]["watched"]), 0, "the watch flag did not clear")

func test_watching_a_fixture_hands_it_to_the_viewer_and_back() -> void:
	var plan: Array = screen().current_view()["plan"]
	var toggle_id := "toggle:" + str(plan[0]["id"])
	press_id(toggle_id)
	press_id("fixture:" + str(plan[0]["id"]))
	assert_false(game.paused, "the watched match did not start")
	assert_eq(str(game.home_id), str(plan[0]["home_club_id"]), "the viewer started another fixture")
	game.engine.score[0] = 3
	game.engine.score[1] = 0
	game.engine.phase = "full_time"
	game._process(0.016)
	assert_true(game.menus.league_active(), "the hub did not come back after full time")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "the result did not land on the hub")
	var stored := LeagueSeason.active.report(str(plan[0]["id"]))
	assert_true(bool(stored["played"]), "the watched result is not on the save")
	assert_eq((stored["score"] as Array)[0], 3, "the watched score is wrong")

func test_continue_plays_the_autos_and_shows_the_roundup() -> void:
	var before := int(LeagueSeason.active.record.played())
	press_id("continue")
	if screen().mode == LeagueScreen.MODE_REPORT:
		var results: Array = screen().roundup
		assert_gt(results.size(), 0, "the roundup is empty")
		assert_eq(int(LeagueSeason.active.record.played()), before + results.size(), "the ledger lost matches")
		press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Continue did not settle on the hub")
	assert_gte(int(LeagueSeason.active.record.played()), before, "the ledger went backwards")

func test_the_table_shows_the_saved_bands() -> void:
	press_id("table")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "the table did not open")
	var rows: Array = screen().current_view()["table"]
	assert_eq(rows.size(), 20, "the table is short")
	var cucl := false
	var crel := false
	for item in screen().buttons:
		if str(item["kind"]) == "table_row":
			cucl = cucl or str(item["zone"]) == "ucl"
			crel = crel or str(item["zone"]) == "relegation"
	assert_true(cucl, "the table has no European band")
	assert_true(crel, "the table has no relegation band")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Back did not leave the table")

func test_the_calendar_opens_a_day_and_a_report() -> void:
	press_id("calendar")
	assert_eq(screen().mode, LeagueScreen.MODE_CALENDAR, "the calendar did not open")
	var day_id := ""
	for item in screen().buttons:
		if str(item["kind"]) == "cell" and int((item["info"] as Dictionary).get("n", 0)) > 0:
			day_id = str(item["id"])
			break
	assert_true(day_id != "", "no day has fixtures")
	press_id(day_id)
	assert_gt(screen().day_fixtures.size(), 0, "the day list is empty")
	press_id("month:1")
	var next_month := str(screen().current_view()["month"])
	assert_ne(next_month, "", "the month did not move")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Back did not leave the calendar")

func test_the_podium_reads_a_finished_season() -> void:
	var season := LeagueSeason.active
	PLDatabase.execute("UPDATE league_fixture SET home_goals = 1, away_goals = 0, status = 'played';")
	season.record.recompute_table()
	season.save.set_status("complete")
	season.save.reload()
	screen().open_season(season)
	assert_eq(screen().mode, LeagueScreen.MODE_PODIUM, "a finished season did not land on the podium")
	var summary: Dictionary = screen().current_view()["summary"]
	assert_false(summary.is_empty(), "the podium has no summary")
	assert_eq((summary["relegated"] as Array).size(), 3, "the podium lost the drop")
	var champion := str(summary["champion"]["club"])
	assert_true(champion != "", "the podium has no champion")
	press_id("menu")
	assert_false(game.menus.league_active(), "Main Menu did not leave the league")

func test_the_load_list_opens_and_deletes_a_save() -> void:
	game.menus.open_menu()
	press(door("load_league").get_center())
	assert_eq(screen().mode, LeagueScreen.MODE_LOAD, "Load League did not open the list")
	assert_gte(screen().saves.size(), 1, "the load list is empty")
	var slug := str(screen().saves[0]["slug"])
	press_id("open:" + slug)
	assert_true(screen().mode == LeagueScreen.MODE_HUB or screen().mode == LeagueScreen.MODE_PODIUM,
		"opening a save did not land on its season")
	press_id("menu")
	game.menus.open_menu()
	press(door("load_league").get_center())
	var count_before: int = screen().saves.size()
	press_id("delete:" + str(screen().saves[0]["slug"]))
	assert_eq(screen().saves.size(), count_before - 1, "the delete door did not remove the save")

func test_a_phone_viewport_still_hits_every_door() -> void:
	var original: Vector2 = game.menus.league.screen.design_vp()
	var fixtures: Array = []
	for i in range(10):
		fixtures.append({"id": "gw01-A%d-B%d" % [i, i], "home_abbr": "HOM", "away_abbr": "AWY",
			"kickoff_time": "15:00", "kickoff": "2026-08-15", "watched": 0 if i % 2 == 0 else 1,
			"suggested": 0, "status": "pending", "home_goals": 0, "away_goals": 0})
	var table: Array = []
	for i in range(20):
		table.append({"position": i + 1, "club_id": "C%d" % i, "club_abbr": "C%d" % i,
			"played": 0, "gf": 0, "ga": 0, "points": 0})
	var state := {"name": "X", "day": "SAT 15 AUG", "matchday": 1, "played": 0, "total": 380,
		"plan": fixtures, "table": table, "rules": LeagueRules.defaults(),
		"can_suggest": false, "complete": false}
	for size in [Vector2(1600, 900), Vector2(913, 411)]:
		var sheet := LeagueSheet.new()
		for item in sheet.hub_layout(size, state):
			var rect: Rect2 = item["rect"]
			assert_gte(rect.size.y, 16.0, "a hub row is too short at %s" % size)
			assert_lte(rect.end.y, size.y, "a hub row runs off the bottom at %s" % size)
	assert_gt(original.x, 0.0, "the live viewport collapsed")

func test_every_league_pose_draws() -> void:
	game.menus.open_menu()
	press(door("new_league").get_center())
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	press_id("create")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "the draw walk could not create a season")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	press_id("table")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	press_id("back")
	press_id("calendar")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	for item in screen().buttons:
		if str(item["kind"]) == "cell":
			press_id(str(item["id"]))
			break
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	press_id("back")
	press_id("continue")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	if screen().mode == LeagueScreen.MODE_REPORT:
		press_id("back")
	var active := LeagueSeason.active
	PLDatabase.execute("UPDATE league_fixture SET home_goals = 2, away_goals = 2, status = 'played';")
	active.record.recompute_table()
	active.save.set_status("complete")
	active.save.reload()
	screen().open_season(active)
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	assert_eq(screen().mode, LeagueScreen.MODE_PODIUM, "the podium did not draw")
	press_id("menu")
	assert_false(game.menus.league_active(), "the draw walk did not leave the league")

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		DirAccess.make_dir_recursive_absolute(folder)
		for name in DirAccess.get_files_at(folder):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(folder.path_join(name)))
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
