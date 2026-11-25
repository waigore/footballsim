extends GdToolsTest

## The league surfaces driven through the real scene: menu doors, the setup
## wizard, the planner and Continue loop, a watched fixture, the table, the
## calendar, reports and the podium.

var SAVE_DIR := TestScratch.dir("saves_test_ui_issue58")
var CACHE_DIR := TestScratch.dir("cache_test_ui_issue58")
var PREFS := TestScratch.file("test_league_ui_issue58.cfg")

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

func key(code: int) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.pressed = true
	game._input(ev)

func screen():
	return game.menus.league.screen

## A press that hands a watched fixture to the viewer now opens the pre-match
## briefing (#157): the flow kicks it off so the suite keeps driving the sim.
func press_id(id: String) -> void:
	for item in screen().buttons:
		if str(item["id"]) == id:
			press((item["rect"] as Rect2).get_center())
			if TestBriefing.is_open(game):
				assert_true(TestBriefing.kick(game), "the briefing's CONTINUE did not start the match")
			return
	if PANEL_DOORS.has(id):
		_press_panel_row(str(PANEL_DOORS[id]))
		return
	assert_true(false, "no button %s on screen %s" % [id, screen().mode])
## Doors that moved into the left panel (#105): the season sheets no longer carry
## a bottom door bar, so a suite that asks for one presses the panel row instead.
const PANEL_DOORS := {
	"system": "nav:system", "table": "nav:table", "calendar": "nav:calendar",
	"stats": "nav:stats", "interest": "nav:interest", "podium": "stats:podium",
}

func _press_panel_row(id: String) -> void:
	var panel: LeaguePanel = screen().panel
	panel.open()
	panel.settle()
	screen().refresh()
	if id.begins_with("nav:"):
		for i in range(LeaguePanel.ITEMS.size()):
			if str(LeaguePanel.ITEMS[i]["id"]) == id:
				press(panel.item_rect(screen().design_vp(), i).get_center())
				panel.settle()
				return
	# A second hop, e.g. Podium on the Stats sheet.
	for item in screen().buttons:
		if str(item["id"]) == id:
			press((item["rect"] as Rect2).get_center())
			panel.settle()
			return
	assert_true(false, "no panel door %s" % id)


## Leaving the season now runs through the System sheet (#109): the hub's fourth
## door opens it and its MAIN MENU row leaves for the menu. The podium keeps its
## own MAIN MENU door, so that one is pressed where it exists.
func _leave_season() -> void:
	for item in screen().buttons:
		if str(item["id"]) == "menu":
			press((item["rect"] as Rect2).get_center())
			return
	press_id("system")
	press_id("sys:menu")

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
	var fixture_id := str(plan[0]["id"])
	var day := str(LeagueSeason.active.state()["date"])
	press_id("toggle:" + fixture_id)
	press_id("fixture:" + fixture_id)
	assert_false(game.paused, "the watched match did not start")
	assert_eq(str(game.home_id), str(plan[0]["home_club_id"]), "the viewer started another fixture")
	game.engine.score[0] = 3
	game.engine.score[1] = 0
	game.engine.phase = "full_time"
	game._process(0.016)
	# #124: the whistle keeps the broadcast on its FULL TIME card; the season is
	# one tap behind it, with the result already saved.
	assert_false(game.menus.league_active(), "the hub took the screen before the card was read")
	assert_true(game.menus.league_holding(), "the finished broadcast was not held")
	assert_true(bool(game.hud_layer.visible), "the FULL TIME card was hidden with the whistle")
	assert_true(bool(game.result_hold), "the broadcast was not told to hold")
	# The card owns the ended game: a match control does nothing to it, and a
	# report for another fixture is not this hold.
	key(KEY_R)
	assert_true(game.menus.league_holding(), "a key dismissed the card by accident")
	assert_eq(str(game.engine.phase), "full_time", "R restarted a fixture already in the ledger")
	assert_false(game.menus.league.result.take({}), "an unrelated report took the held card")
	key(KEY_SPACE)
	assert_true(game.menus.league_active(), "the dismissed card did not hand the hub back")
	assert_false(bool(game.result_hold), "the broadcast is still holding the card")
	assert_false(bool(game.hud_layer.visible), "the broadcast stayed over the hub")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "the result did not land on the hub")
	var stored := LeagueSeason.active.report(fixture_id)
	assert_true(bool(stored["played"]), "the watched result is not on the save")
	assert_eq((stored["score"] as Array)[0], 3, "the watched score is wrong")
	# The played day stays on the hub, its row reading as a result: FT, the score
	# where the chip was, and no watch door left to press.
	assert_eq(str(LeagueSeason.active.state()["date"]), day, "the hub left the day it just played")
	var row := {}
	for fx in screen().current_view()["plan"]:
		if str(fx["id"]) == fixture_id:
			row = fx
	assert_false(row.is_empty(), "the played fixture left the hub")
	assert_eq(str(row["status"]), "played", "the hub row is not marked played")
	assert_eq(int(row["home_goals"]), 3, "the hub row lost the score")
	for item in screen().buttons:
		assert_ne(str(item["id"]), "toggle:" + fixture_id, "a played row still offers AUTO/WATCH")

func test_continue_plays_the_autos_and_shows_the_roundup() -> void:
	var before := int(LeagueSeason.active.record.fixtures.played())
	press_id("continue")
	if screen().mode == LeagueScreen.MODE_REPORT:
		var results: Array = screen().roundup
		assert_gt(results.size(), 0, "the roundup is empty")
		assert_eq(int(LeagueSeason.active.record.fixtures.played()), before + results.size(), "the ledger lost matches")
		press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Continue did not settle on the hub")
	assert_gte(int(LeagueSeason.active.record.fixtures.played()), before, "the ledger went backwards")

## #100: Continue on a day that still holds watches hands the viewer the next
## watched fixture instead of settling the day and leaving the hub as it was.
func test_continue_opens_the_pending_watch() -> void:
	var plan := _matchday_hub()
	var held := str(plan[0]["id"])
	if int(plan[0]["watched"]) != 1:
		press_id("toggle:" + held)
	press_id("continue")
	assert_false(game.paused, "Continue did not open the watched match")
	assert_eq(str(game.home_id), str(plan[0]["home_club_id"]), "Continue opened another fixture")
	assert_eq(LeagueSeason.active.watching_fixture, held, "the season is not waiting for that watch")
	game.engine.score[0] = 2
	game.engine.score[1] = 1
	game.engine.phase = "full_time"
	game._process(0.016)
	# #124: the whistle holds the full-time card; a tap hands the hub back.
	assert_true(game.menus.league_holding(), "Continue's watch skipped its full-time card")
	press(Vector2(400.0, 200.0))
	assert_true(game.menus.league_active(), "the hub did not come back after the card")
	var stored := LeagueSeason.active.report(held)
	assert_true(bool(stored["played"]), "Continue's watch was not saved")
	assert_eq(int((stored["score"] as Array)[0]), 2, "the watched score was not stored")

## #100: leaving the viewer before full time plays the rest out on the physical
## engine at max speed and saves it, so the hub shows the same result a
## full-time watch would have left.
func test_leaving_a_watch_early_finishes_and_saves_it() -> void:
	assert_false(game.menus.league.watch.leave(), "a season with nothing watched left the viewer")
	var plan := _matchday_hub()
	var held := str(plan[0]["id"])
	if int(plan[0]["watched"]) != 1:
		press_id("toggle:" + held)
	press_id("continue")
	assert_false(game.paused, "Continue did not open the watched match")
	# Park the match one tick short of full time: the settle has to play the rest
	# itself, and the suite must not sit through 90 minutes under coverage.
	game.engine.half = 2
	game.engine.clock = 5399.9
	game.engine.added[1] = 0.0
	game.menus.open_menu()
	assert_true(game.menus.league_active(), "MENU left the season")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "MENU did not land on the hub")
	assert_true(bool(screen().current_view().get("settling", false)), "the hub hides the finishing match")
	assert_true(game.menus.league.watch.settling(), "the host is not finishing the match")
	# The sheet's own frame is what drives the leftover match.
	screen().body._process(0.016)
	for i in range(60):
		if not game.menus.league.watch.settling():
			break
		game.menus.league.watch.tick()
	assert_false(game.menus.league.watch.settling(), "the match never finished")
	assert_true(game.menus.league_active(), "the hub did not stay up for the result")
	var stored := LeagueSeason.active.report(held)
	assert_true(bool(stored["played"]), "the left-behind watch was not saved")
	assert_eq(int((stored["score"] as Array)[0]), int(game.engine.score[0]),
		"the saved score is not the engine's")
	assert_false(bool(screen().current_view().get("settling", false)), "the hub still says finishing")
	_leave_season()

## #100: a leftover watch that finishes while the main menu is open saves its
## result without popping the season sheet over the menu.
func test_a_leftover_watch_finishes_behind_the_main_menu() -> void:
	var plan := _matchday_hub()
	var held := str(plan[0]["id"])
	if int(plan[0]["watched"]) != 1:
		press_id("toggle:" + held)
	press_id("continue")
	assert_false(game.paused, "Continue did not open the watched match")
	game.engine.half = 2
	game.engine.clock = 5399.9
	game.engine.added[1] = 0.0
	game.menus.open_menu()
	_leave_season()
	assert_true(game.menus.shell.active(), "the hub's MENU did not reach the main menu")
	assert_false(bool(game.menus.league.layer.visible), "the hub stayed over the menu")
	for i in range(60):
		if not game.menus.league.watch.settling():
			break
		game.menus.league.watch.tick()
	assert_false(game.menus.league.watch.settling(), "the leftover match never finished")
	assert_true(bool(LeagueSeason.active.report(held)["played"]), "the result was lost behind the menu")
	assert_false(bool(game.menus.league.layer.visible), "the hub popped over the main menu")
	game.menus.shell.close()

func test_a_report_play_door_plays_the_stored_clip_and_comes_back() -> void:
	var season := LeagueSeason.active
	var fixture := ""
	for row in season.record.fixtures.all():
		if not season.record.clips.list(str(row["id"])).is_empty():
			fixture = str(row["id"])
			break
	assert_true(fixture != "", "no fixture has a stored clip")
	game.menus.league.show_season(season)
	screen().show_report(fixture)
	assert_eq(screen().mode, LeagueScreen.MODE_REPORT, "the report did not open")
	var door := ""
	for item in screen().buttons:
		if str(item["id"]).begins_with("goal:"):
			door = str(item["id"])
			break
	assert_true(door != "", "the report offers no play door")
	press_id(door)
	assert_not_null(game.replay, "the play door did not start a clip")
	assert_false(bool(game.menus.league.layer.visible), "the report stayed over the pitch")
	assert_true(str(game.home_id) != "" and str(game.away_id) != "", "the viewer has no clubs")
	var clock_before := float(game.engine.clock)
	for i in range(24):
		game._process(0.1)
	assert_gt(float(game.engine.clock), clock_before, "the clip is not playing")
	game._skip()
	assert_eq(screen().mode, LeagueScreen.MODE_REPORT, "skipping did not return to the report")
	assert_true(bool(game.menus.league.layer.visible), "the report did not come back")
	screen().open_season(season)

func test_the_number_keys_play_report_goals() -> void:
	var season := LeagueSeason.active
	var fixture := ""
	# The report with the fewest goals: the key beyond the last one must find
	# nothing, whatever the season's high scores look like.
	var fewest := 1 << 30
	for row in season.record.fixtures.all():
		var goals := season.record.clips.list(str(row["id"])).size()
		if goals > 0 and goals < fewest:
			fewest = goals
			fixture = str(row["id"])
	game.menus.league.show_season(season)
	screen().show_report(fixture)
	assert_eq(screen().mode, LeagueScreen.MODE_REPORT, "the report did not open")
	assert_true(screen().key(KEY_1), "the first goal key was not taken")
	assert_not_null(game.replay, "the key did not start a clip")
	assert_false(screen().has_clip(fewest), "a goal beyond the report claims a clip")
	game._skip()
	assert_null(game.replay, "the clip did not end")
	screen().open_season(season)

func test_the_report_still_reads_a_goal_less_match() -> void:
	var season := LeagueSeason.active
	game.menus.league.show_season(season)
	screen().report = {"fixture": {"id": "", "home_name": "Home", "away_name": "Away"}, "events": [], "highlights": []}
	screen().mode = LeagueScreen.MODE_REPORT
	screen().refresh()
	assert_false(screen().has_clip(0), "an empty report claims a clip")
	screen().click("goal:0")
	assert_null(game.replay, "an empty report started a clip")
	assert_eq(screen().mode, LeagueScreen.MODE_REPORT, "the empty report left")
	screen().open_season(LeagueSeason.active)

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
	season.record.standings.recompute()
	season.save.set_status("complete")
	season.save.reload()
	screen().open_season(season)
	assert_eq(screen().mode, LeagueScreen.MODE_PODIUM, "a finished season did not land on the podium")
	var summary: Dictionary = screen().current_view()["summary"]
	assert_false(summary.is_empty(), "the podium has no summary")
	assert_eq((summary["relegated"] as Array).size(), 3, "the podium lost the drop")
	var champion := str(summary["champion"]["club"])
	assert_true(champion != "", "the podium has no champion")
	_leave_season()
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
	_leave_season()
	game.menus.open_menu()
	press(door("load_league").get_center())
	var count_before: int = screen().saves.size()
	var victim := str(screen().saves[0]["slug"])
	press_id("delete:" + victim)
	assert_true(screen().delete.is_open(), "the delete door did not ask")
	assert_eq(screen().saves.size(), count_before, "the save went before the answer")
	press(ConfirmPrompt.confirm_rect(vp()).get_center())
	assert_eq(screen().saves.size(), count_before - 1, "the delete door did not remove the save")
	assert_eq(screen().mode, LeagueScreen.MODE_LOAD, "answering DELETE left the load list")

## A library longer than the window is read by scrolling: a row past the fold
## must not answer a press until the list brings it into view (REQ-P5-08).
func test_every_save_on_a_long_load_list_is_reachable() -> void:
	game.menus.open_menu()
	press(door("load_league").get_center())
	var many: Array = []
	for i in range(30):
		many.append({"slug": "lib%d" % i, "name": "Library %d" % i, "status": "in_progress",
			"current_date": "2026-09-01", "matchday": i + 1, "path": "", "modified": i})
	screen().saves = many
	screen().body.scroll_to(0.0)
	screen().refresh()
	var tail := "open:lib29"
	var row := Rect2()
	var laid := false
	for item in screen().buttons:
		if str(item["id"]) == tail:
			row = item["rect"]
			laid = true
	assert_true(laid, "the last save was laid out nowhere")
	assert_gt(row.end.y, screen().design_vp().y, "the last save already fits; the case proves nothing")
	assert_eq(screen().button_at(row.get_center()), "", "a row below the fold answered a press")
	screen().scroll_by(4000.0)
	screen().refresh()
	assert_gt(screen().body.scroll, 0.0, "a load list longer than the window does not scroll")
	for item in screen().buttons:
		if str(item["id"]) == tail:
			row = item["rect"]
	assert_eq(screen().button_at(row.get_center()), tail, "the last save is stranded below the fold")
	screen().saves = []
	screen().body.scroll_to(0.0)
	screen().refresh()

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
	var state := {"name": "X", "day": "15/AUG/2026", "date": "2026-08-15", "matchday": 1,
		"played": 0, "total": 380, "plan": fixtures, "table": table,
		"rules": LeagueRules.defaults(), "can_suggest": false, "complete": false}
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
	active.record.standings.recompute()
	active.save.set_status("complete")
	active.save.reload()
	screen().open_season(active)
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	assert_eq(screen().mode, LeagueScreen.MODE_PODIUM, "the podium did not draw")
	_leave_season()
	assert_false(game.menus.league_active(), "the draw walk did not leave the league")

func test_the_wizard_reports_a_save_it_cannot_open() -> void:
	game.menus.open_menu()
	press(door("new_league").get_center())
	screen().open_save("no-such-save")
	assert_eq(screen().mode, LeagueScreen.MODE_WIZARD, "a broken save did not return to the wizard")
	assert_true(str(screen().wizard["error"]) != "", "the wizard hid the error")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	press_id("back")

func test_keyboard_walks_the_league_and_respects_its_limits() -> void:
	_open_hub()
	var before := int(LeagueSeason.active.record.fixtures.played())
	assert_true(screen().key(KEY_ENTER), "Enter did not press Continue")
	assert_gte(int(LeagueSeason.active.record.fixtures.played()), before, "Enter lost matches")
	# #169: Esc walks the season's own history; at its root it does nothing, so
	# the league is left through System → MAIN MENU.
	assert_true(screen().key(KEY_ESCAPE), "Esc was not taken by the season")
	assert_true(screen().key(KEY_ESCAPE), "Esc was not taken at the root")
	assert_true(game.menus.league_active(), "Esc opened the main menu from the league")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Esc did not land on the hub")
	press_id("system")
	press_id("sys:menu")
	assert_false(game.menus.league_active(), "MAIN MENU left the league open")
	assert_true(game.menus.active(), "MAIN MENU did not return to the main menu")
	game.menus.open_menu()
	press(door("new_league").get_center())
	for i in range(30):
		screen().key(KEY_A)
	assert_lte(str(screen().wizard["name"]).length(), 24, "the name grew past its limit")
	screen().key(KEY_BACKSPACE)
	assert_true(str(screen().wizard["name"]).length() <= 24, "backspace broke the name")
	assert_false(screen().key(KEY_TAB), "an unrelated key was taken")

func test_the_month_doors_and_an_empty_day_draw() -> void:
	_open_hub()
	press_id("calendar")
	var month := str(screen().current_view()["month"])
	press_id("month:-1")
	assert_ne(str(screen().current_view()["month"]), month, "the previous month door did nothing")
	press_id("month:1")
	assert_eq(str(screen().current_view()["month"]), month, "the next month door did not come back")
	var empty_day := ""
	for item in screen().buttons:
		if str(item["kind"]) == "cell" and int((item["info"] as Dictionary).get("n", 0)) == 0:
			empty_day = str(item["id"])
			break
	if empty_day != "":
		press_id(empty_day)
		assert_eq(screen().day_fixtures.size(), 0, "an empty day listed fixtures")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	press_id("back")

func test_a_report_with_every_event_kind_draws() -> void:
	var season := LeagueSeason.active
	var played := season.record.fixtures.all()
	var fixture_id := ""
	for fx in played:
		if str(fx["status"]) == "played":
			fixture_id = str(fx["id"])
			break
	assert_true(fixture_id != "", "there is no played fixture to report")
	var fx := season.record.fixtures.one(fixture_id)
	season.record.report.add_events([
		{"fixture_id": fixture_id, "minute": 1, "kind": "goal", "player_id": "", "club_id": str(fx["home_club_id"]), "detail": "A. Player"},
		{"fixture_id": fixture_id, "minute": 2, "kind": "assist", "player_id": "", "club_id": str(fx["home_club_id"]), "detail": "B. Player"},
		{"fixture_id": fixture_id, "minute": 3, "kind": "yellow", "player_id": "", "club_id": str(fx["away_club_id"]), "detail": "C. Player"},
		{"fixture_id": fixture_id, "minute": 4, "kind": "red", "player_id": "", "club_id": str(fx["away_club_id"]), "detail": "D. Player"},
	])
	screen().open_season(season)
	screen().show_report(fixture_id)
	assert_eq(screen().mode, LeagueScreen.MODE_REPORT, "the report did not open")
	await get_tree().process_frame
	screen().queue_redraw()
	await get_tree().process_frame
	var kinds := {}
	for item in screen().buttons:
		if str(item["kind"]) == "event":
			kinds[str((item["event"] as Dictionary).get("kind", ""))] = true
	assert_true(kinds.has("red"), "the report lost the red card")
	press_id("back")

func test_menu_keys_open_both_league_doors() -> void:
	game.menus.open_menu()
	assert_true(game.menus.shell.key(KEY_N), "N was ignored on the menu")
	assert_true(game.menus.league_active(), "N did not open New League")
	press_id("back")
	game.menus.open_menu()
	assert_true(game.menus.shell.key(KEY_L), "L was ignored on the menu")
	assert_true(game.menus.league_active(), "L did not open Load League")
	press_id("back")

func test_the_host_opens_a_save_by_slug_and_syncs() -> void:
	game.menus.open_menu()
	assert_gte(LeagueSave.list().size(), 1, "there is no save to open")
	var slug := str(LeagueSave.list()[0]["slug"])
	game.menus.league.open_save(slug)
	assert_true(game.menus.league_active(), "the host did not open the save")
	game.menus.league.sync(Transform2D.IDENTITY, 1.0, false)
	assert_true(game.menus.league.is_open(), "syncing closed the league layer")
	_leave_season()
	assert_false(game.menus.league_active(), "the league stayed open after MENU")

func test_table_rows_and_the_podium_door() -> void:
	_open_hub()
	press_id("table")
	var club_id := ""
	for item in screen().buttons:
		if str(item["kind"]) == "table_row":
			club_id = str(item["id"])
			break
	assert_true(club_id != "", "the table laid out no club rows")
	press_id(club_id)
	assert_true(game.wiki_host.is_open(), "a club row did not open the team page")
	game.wiki_host.screen.click("back")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "the club row left the table")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Back did not leave the table")
	LeagueSeason.active.save.set_status("complete")
	screen().refresh()
	# The podium lives under Stats now (#108): the panel opens Stats, its door
	# opens the podium.
	press_id("stats")
	press_id("stats:podium")
	assert_eq(screen().mode, LeagueScreen.MODE_PODIUM, "the Stats podium door did not open")
	assert_false(LeagueSeason.active.summary().is_empty(), "a complete season lost its summary")
	press_id("table")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "the podium table door did not open")
	press_id("back")
	LeagueSeason.active.save.set_status("in_progress")
	screen().open_season(LeagueSeason.active)
	_leave_season()

func test_the_hub_table_row_opens_the_club_page_and_back_returns() -> void:
	_open_hub()
	var club_id := ""
	for item in screen().buttons:
		if str(item["kind"]) == "table_row":
			club_id = str(item["id"])
			break
	assert_true(club_id != "", "the wide hub laid out no club rows")
	press_id(club_id)
	assert_true(game.wiki_host.is_open(), "a hub club row did not open the team page")
	var landed: Dictionary = game.wiki_host.screen.current()
	assert_eq(str(landed["page"]), WikiModel.TEAM, "the hub row opened another page")
	assert_eq(str(landed["id"]), club_id.substr(5), "the hub row opened another club")
	assert_false(game.menus.league_active(), "the season stayed painted under the page")
	game.wiki_host.screen.click("back")
	assert_true(game.menus.league_active(), "Back from the page did not give the season back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "Back from the page lost the hub")
	assert_true(game.paused, "the season resumed the match under it")
	_leave_season()
	assert_false(game.menus.league_active(), "MENU did not leave the season")

func test_pointer_motion_and_drag_are_not_clicks() -> void:
	game.menus.open_menu()
	press(door("new_league").get_center())
	var before := str(screen().wizard["name"])
	var motion := InputEventMouseMotion.new()
	motion.position = Vector2(10, 10) * game.menus.shell.ui_scale
	game._input(motion)
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = Vector2(200, 200)
	game._input(down)
	var drag := InputEventMouseMotion.new()
	drag.position = Vector2(320, 240)
	drag.button_mask = MOUSE_BUTTON_MASK_LEFT
	game._input(drag)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = Vector2(320, 240)
	game._input(up)
	assert_eq(str(screen().wizard["name"]), before, "a drag clicked through to the wizard")
	press_id("back")

func test_deleting_the_active_save_returns_to_the_list() -> void:
	# Reopen a save that already exists: creating one here would add a file the
	# later cases pick as the newest save.
	if LeagueSeason.active == null:
		game.menus.open_menu()
		press(door("load_league").get_center())
		press_id("open:" + str(screen().saves[0]["slug"]))
	var season := LeagueSeason.active
	assert_not_null(season, "no season is active to delete")
	var slug := str(season.save.slug)
	game.menus.open_menu()
	press(door("load_league").get_center())
	press_id("delete:" + slug)
	assert_eq(screen().mode, LeagueScreen.MODE_LOAD, "the delete question left the list")
	press(ConfirmPrompt.confirm_rect(vp()).get_center())
	assert_null(LeagueSeason.active, "the deleted season stayed active")
	assert_null(screen().season, "the screen kept a deleted season")
	assert_eq(screen().mode, LeagueScreen.MODE_LOAD, "the delete did not stay on the list")
	press_id("back")
	assert_true(game.menus.active(), "Back from the load list did not reach the menu")

## #100: a new single match takes the scene from a leftover watch — the season
## lets go of both the fixture and the engine instead of recording it later.
func test_a_new_match_drops_a_leftover_watch() -> void:
	var plan := _matchday_hub()
	var held := str(plan[0]["id"])
	press_id("toggle:" + held)
	press_id("continue")
	assert_false(game.paused, "Continue did not open the watched match")
	assert_true(game.menus.league.watch.leave(), "the viewer did not hand the season back")
	assert_false(game.menus.league.watch.leave(), "the leftover match left twice")
	game.menus.league.detach_season()
	assert_false(game.menus.league.watch.settling(), "the leftover match outlived its season")
	assert_null(game.menus.league.season, "the host kept the season a friendly took")
	assert_null(LeagueSeason.active, "the season stayed bound to the cached seed")
	game.paused = true

# ---------------------------------------------------------------- scroll ---

func test_a_phone_table_scrolls_by_drag_wheel_pan_and_keys() -> void:
	_open_scroll_hub()
	var saved: float = screen().ui_scale
	_phone_scale()
	press_id("table")
	assert_true(screen().body.clip_contents, "the season body does not clip its content")
	assert_gt(screen().body.max_scroll(), 0.0, "the table should overflow a phone viewport")
	_drag(Vector2(400.0, 300.0), Vector2(400.0, 180.0))
	assert_gt(screen().body.scroll, 0.0, "a finger drag did not scroll the table")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "the drag clicked through a row")
	screen().body.scroll_to(0.0)
	var host = game.menus.league
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	wheel.pressed = true
	host.handle_input(wheel, Vector2(400.0, 200.0))
	assert_gt(screen().body.scroll, 0.0, "a wheel notch did not scroll the table")
	screen().body.scroll_to(0.0)
	var pan := InputEventPanGesture.new()
	pan.delta = Vector2(0.0, 2.0)
	host.handle_input(pan, Vector2.ZERO)
	assert_gt(screen().body.scroll, 0.0, "a trackpad pan did not scroll the table")
	assert_true(screen().key(KEY_END), "END was ignored")
	assert_almost_eq(screen().body.scroll, screen().body.max_scroll(), 0.5, "END did not reach the last row")
	assert_true(screen().key(KEY_HOME), "HOME was ignored")
	assert_eq(screen().body.scroll, 0.0, "HOME did not return to the top")
	assert_true(screen().key(KEY_PAGEDOWN), "PAGE DOWN was ignored")
	assert_gt(screen().body.scroll, 0.0, "PAGE DOWN did not scroll")
	press_id("back")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "BACK left the table")
	assert_eq(screen().body.scroll, 0.0, "a new pose should start at the top")
	screen().ui_scale = saved
	screen().refresh()

func test_a_row_scrolled_into_view_is_the_one_that_opens() -> void:
	_open_scroll_hub()
	var saved: float = screen().ui_scale
	_phone_scale()
	press_id("table")
	var last_id := ""
	var last_bottom := 0.0
	for item in screen().buttons:
		if str(item["id"]).begins_with("club:"):
			last_id = str(item["id"])
			last_bottom = (item["rect"] as Rect2).end.y
	assert_true(last_id != "", "the table laid out no clubs")
	assert_gt(last_bottom, screen().body.position.y + screen().body.size.y,
		"the last club should start below the fold")
	screen().body.scroll_to(screen().body.max_scroll())
	var target: Dictionary = {}
	for item in screen().buttons:
		if str(item["id"]) == last_id:
			target = item
	assert_false(target.is_empty(), "the last club vanished after the scroll")
	if target.is_empty():
		screen().ui_scale = saved
		return
	assert_lte((target["rect"] as Rect2).end.y,
		screen().body.position.y + screen().body.size.y + 0.5, "the last club is still under the footer")
	press((target["rect"] as Rect2).get_center())
	assert_true(game.wiki_host.is_open(), "the scrolled club row did not open its page")
	var landed: Dictionary = game.wiki_host.screen.current()
	assert_eq(str(landed["page"]), WikiModel.TEAM, "the scrolled row opened another page")
	assert_eq(str(landed["id"]), last_id.substr(5), "the scrolled row opened another club")
	game.wiki_host.screen.click("close")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "closing the page left the table")
	screen().ui_scale = saved
	screen().refresh()

func test_the_body_clamps_its_scroll_to_the_content() -> void:
	var body := LeagueBody.new()
	body.size = Vector2(400.0, 200.0)
	body.content_height = 500.0
	body.scroll_by(-100.0)
	assert_eq(body.scroll, 0.0, "the body scrolled above its first row")
	body.scroll_by(10000.0)
	assert_almost_eq(body.scroll, 300.0, 0.5, "the body did not stop at its last row")
	body.free()

# ------------------------------------------------------------- table view ---

## #74: the table opens on the device default, the mode door switches it, and
## the choice is written to the save so reopening the season brings it back.
func test_the_table_remembers_its_mode_in_the_save() -> void:
	_open_scroll_hub()
	var slug := str(LeagueSeason.active.save.slug)
	press_id("table")
	var view = screen().book.table
	assert_eq(view.mode, LeagueTableView.FULL, "a desktop sheet did not open the full table")
	var heads := 0
	for item in screen().buttons:
		if str(item["kind"]) == "head":
			heads += 1
	assert_eq(heads, 22, "the full header lost a column")
	press_id("tbl:mode:compact")
	assert_eq(view.mode, LeagueTableView.COMPACT, "the mode door did not switch to compact")
	var stored: Dictionary = LeagueSeason.active.save.read_meta()
	assert_eq(str(stored.get("table_mode", "")), "compact", "the mode was not written to the save")
	press_id("back")
	LeagueSeason.active.close()
	var reopened := LeagueSeason.open(slug)
	assert_not_null(reopened, "the save did not reopen")
	screen().open_season(reopened)
	press_id("table")
	assert_eq(view.mode, LeagueTableView.COMPACT, "the reopened season forgot its table reading")
	heads = 0
	for item in screen().buttons:
		if str(item["kind"]) == "head":
			heads += 1
	assert_eq(heads, 10, "the compact header should be #, club and the whole overall record")
	press_id("back")
	_leave_season()

## A header sorts the player's list; the place numbers and their bands stay the
## league's. The second tap reverses, and the choice survives a re-open.
func test_a_table_header_sorts_and_keeps_the_official_place() -> void:
	_open_scroll_hub()
	press_id("continue")
	if screen().mode == LeagueScreen.MODE_REPORT:
		press_id("back")
	press_id("table")
	press_id("tbl:sort:club")
	var names: Array = []
	for item in screen().buttons:
		if str(item["kind"]) == "table_row":
			var row: Dictionary = item["row"]
			names.append(str(row["club_name"]))
			assert_eq(str(item["zone"]), LeagueRules.zone(int(row["position"]), LeagueRules.defaults()),
				"a zone band left its official place")
	assert_eq(names.size(), 20, "the sorted table lost rows")
	var expected := names.duplicate()
	expected.sort()
	assert_eq(names, expected, "the rows are not in club order")
	press_id("tbl:sort:club")
	var reversed: Array = []
	for item in screen().buttons:
		if str(item["kind"]) == "table_row":
			reversed.append(str((item["row"] as Dictionary)["club_name"]))
	expected.reverse()
	assert_eq(reversed, expected, "the second tap did not reverse the sort")
	var stored: Dictionary = LeagueSeason.active.save.read_meta()
	assert_eq(str(stored.get("table_sort", "")), "club", "the sort was not written to the save")
	assert_eq(str(stored.get("table_dir", "")), "desc", "the direction was not written to the save")
	press_id("back")
	press_id("table")
	assert_eq(screen().book.table.sort, "club", "the table forgot its sort")
	assert_eq(screen().book.table.dir, -1, "the table forgot its direction")
	press_id("back")
	_leave_season()

## The full table is wider than a phone in portrait; a sideways drag reaches the
## far columns and the compact reading fits again.
func test_the_full_table_pans_sideways_on_a_phone() -> void:
	_open_scroll_hub()
	var saved: float = screen().ui_scale
	_phone_scale()
	press_id("table")
	var view = screen().book.table
	assert_eq(view.mode, LeagueTableView.COMPACT, "a phone did not open the compact table")
	press_id("tbl:mode:full")
	assert_eq(view.mode, LeagueTableView.FULL, "the mode door did not switch to full")
	assert_gt(screen().body.max_hscroll(), 0.0, "the full table should be wider than the phone")
	_drag(Vector2(500.0, 250.0), Vector2(300.0, 250.0))
	assert_gt(screen().body.hscroll, 0.0, "a sideways drag did not pan the table")
	assert_eq(screen().mode, LeagueScreen.MODE_TABLE, "the sideways drag clicked through a row")
	press_id("tbl:mode:compact")
	assert_eq(view.mode, LeagueTableView.COMPACT, "the mode door did not come back to compact")
	assert_eq(screen().body.max_hscroll(), 0.0, "the compact table should fit the phone")
	press_id("back")
	screen().ui_scale = saved
	screen().refresh()
	_leave_season()

## The hub's date is a date like any other: hovering it hands the overlay that
## exact day, so the weekday never has to ride the date itself (#99).
func test_the_hub_date_reveals_its_weekday_on_hover() -> void:
	_open_scroll_hub()
	screen().queue_redraw()
	await get_tree().process_frame
	var zone: Dictionary = {}
	for z in screen().hints.zones:
		zone = z
	assert_false(zone.is_empty(), "the hub painted no date")
	var date := str(zone["date"])
	screen().mouse = (zone["rect"] as Rect2).get_center()
	assert_eq(str(screen().tooltip.zone_at().get("date", "")), date,
		"a hovered hub date did not reach the overlay")
	assert_eq(FixtureCalendar.day_label(date), str(LeagueSeason.active.state()["day"]),
		"the hub date and the season clock disagree")
	_leave_season()

## The scroll tests create their own season: earlier cases are free to delete
## every save in the list.
func _open_scroll_hub() -> void:
	game.menus.open_menu()
	press(door("new_league").get_center())
	press_id("create")
	assert_eq(screen().mode, LeagueScreen.MODE_HUB, "could not open a season to scroll")

func _phone_scale() -> void:
	# Shrink the design space the way the handheld overlay scale does (main.gd):
	# a phone's short edge becomes the design height, whatever the window is.
	var height: float = screen().size.y
	screen().ui_scale = maxf(height / 411.0, 1.0)
	screen().refresh()
	assert_almost_eq(screen().design_vp().y, minf(height, 411.0), 1.0, "the design space did not shrink")

func _drag(from: Vector2, to: Vector2, steps: int = 4) -> void:
	var host = game.menus.league
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	host.handle_input(down, from)
	var p := from
	for i in range(1, steps + 1):
		p = from.lerp(to, float(i) / float(steps))
		var motion := InputEventMouseMotion.new()
		motion.position = p
		host.handle_input(motion, p)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	host.handle_input(up, p)

func _open_hub() -> void:
	game.menus.open_menu()
	press(door("load_league").get_center())
	press_id("open:" + str(screen().saves[0]["slug"]))
	if screen().mode == LeagueScreen.MODE_PODIUM:
		LeagueSeason.active.save.set_status("in_progress")
		screen().open_season(LeagueSeason.active)

## The shared save advances a day at a time, so most days are empty: walk the
## clock like a player would until the hub lists a matchday with fixtures. A run
## whose earlier cases deleted every save starts a fresh season instead.
func _matchday_hub() -> Array:
	if LeagueSave.list().is_empty():
		_open_scroll_hub()
	else:
		_open_hub()
	var plan: Array = screen().current_view().get("plan", [])
	var guard := 0
	while plan.is_empty() and guard < 30:
		if screen().mode != LeagueScreen.MODE_HUB:
			press_id("back")
		press_id("continue")
		plan = screen().current_view().get("plan", [])
		guard += 1
	assert_gte(plan.size(), 1, "the hub never reached a matchday")
	return plan

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
