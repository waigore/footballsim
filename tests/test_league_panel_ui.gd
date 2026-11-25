extends GdToolsTest

## The left panel, Teams of Interest and Stats driven through the real scene:
## the hub without its bottom door bar, BACK/CONTINUE in the header, panel
## navigation to every destination, the shortlist's search/add/remove, and the
## Stats reports and podium door (#103, #105, #106, #108, #110).

var SAVE_DIR := TestScratch.dir("saves_test_panel_103")
var CACHE_DIR := TestScratch.dir("cache_test_panel_103")
var PREFS := TestScratch.file("test_league_panel_103.cfg")

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
			game.menus.league.detach_season()
			game.menus.league.close()
		game.queue_free()
		await get_tree().process_frame
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func screen():
	return game.menus.league.screen

func panel() -> LeaguePanel:
	return screen().panel

func vp() -> Vector2:
	return screen().design_vp()

func press(p: Vector2) -> void:
	for down in [true, false]:
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.pressed = down
		ev.position = p * game.menus.shell.ui_scale
		game._input(ev)

func press_id(id: String) -> void:
	for item in screen().buttons:
		if str(item["id"]) == id:
			press((item["rect"] as Rect2).get_center())
			return
	assert_true(false, "no button %s on screen %s" % [id, screen().mode])

## The panel's tab, then the slide settled: a row's hit target travels with it.
func open_panel() -> void:
	if panel().target < 0.5:
		panel().open()
	panel().settle()
	screen().refresh()

func press_nav(id: String) -> void:
	open_panel()
	for i in range(LeaguePanel.ITEMS.size()):
		if str(LeaguePanel.ITEMS[i]["id"]) == id:
			press(panel().item_rect(vp(), i).get_center())
			panel().settle()
			return
	assert_true(false, "no panel row %s" % id)

func new_season() -> void:
	game.menus.open_menu()
	press(_menu_door("new_league").get_center())
	press_id("create")
	assert_eq(screen().mode, "hub", "could not open a season")

func _menu_door(id: String) -> Rect2:
	for b in MenuScreen.door_rects(game.menus.shell.design_vp(), bool(game.menus.shell.has_match)):
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

# ------------------------------------------------------------------ chrome ---

func test_the_hub_has_no_bottom_door_bar_and_keeps_back_and_continue() -> void:
	new_season()
	var ids: Array = []
	var back := Rect2()
	var cont := Rect2()
	for item in screen().buttons:
		ids.append(str(item["id"]))
		if str(item["id"]) == "back":
			back = item["rect"]
		if str(item["id"]) == "continue":
			cont = item["rect"]
	for gone in ["table", "calendar", "system"]:
		assert_false(ids.has(gone), "the hub still carries the %s door" % gone)
	assert_true(ids.has("continue"), "the hub lost CONTINUE")
	assert_true(ids.has("back"), "the hub lost BACK")
	assert_almost_eq(back.position.x, 24.0, 0.5, "BACK is not top-left")
	assert_almost_eq(cont.end.x, vp().x - 24.0, 0.5, "CONTINUE is not top-right")
	assert_lte(back.end.y, LeagueSheet.HEADER, "BACK left the header")
	assert_lte(cont.end.y, LeagueSheet.HEADER, "CONTINUE left the header")
	# The body now runs to the window's bottom edge: no bar is reserved.
	assert_almost_eq(screen().body.size.y, vp().y - LeagueBody.TOP, 0.5,
		"the hub still reserves a bottom bar")
	press_id("back")
	assert_false(game.menus.league_active(), "BACK on the hub did not leave the league")

# ------------------------------------------------------------------- panel ---

func test_the_panel_slides_open_navigates_and_closes() -> void:
	new_season()
	assert_false(panel().is_open(), "the panel opened by itself")
	press(panel().tab_rect(vp()).get_center())
	assert_true(panel().is_open(), "the panel did not open")
	panel().update(0.5)
	assert_almost_eq(panel().slide, 1.0, 0.01, "the panel did not settle open")
	assert_true(panel().item_rect(vp(), 0).position.x > 0.0, "the rows did not slide in")
	press_nav("nav:table")
	assert_eq(screen().mode, "table", "the panel did not open the table")
	assert_false(panel().is_open(), "the panel stayed open over the table")
	open_panel()
	press_nav("nav:calendar")
	assert_eq(screen().mode, "calendar", "the panel did not open the calendar")
	open_panel()
	press_nav("nav:fixtures")
	assert_eq(screen().mode, "hub", "Today's Fixtures did not come back")
	# A scrim press closes the panel and leaves the sheet where it was.
	open_panel()
	press(Vector2(vp().x - 30.0, vp().y * 0.5))
	panel().settle()
	assert_false(panel().is_open(), "a press beside the panel did not close it")
	assert_eq(screen().mode, "hub", "closing the panel changed the sheet")

func test_every_panel_destination_opens() -> void:
	new_season()
	for pair in [["nav:table", "table"], ["nav:calendar", "calendar"], ["nav:interest", "interest"],
			["nav:stats", "stats"], ["nav:system", "system"], ["nav:fixtures", "hub"]]:
		press_nav(str(pair[0]))
		assert_eq(screen().mode, str(pair[1]), "the panel did not open %s" % pair[1])
		screen().queue_redraw()
		await get_tree().process_frame
	assert_eq(screen().mode, "hub", "the last destination did not land on the hub")

func test_the_panel_icons_are_distinct_assets() -> void:
	var seen := {}
	for item in LeaguePanel.ITEMS:
		var path := "res://assets/ui/league/%s.png" % str(item["icon"])
		assert_true(ResourceLoader.exists(path), "no icon for %s" % item["icon"])
		assert_false(seen.has(path), "two panel rows share an icon")
		seen[path] = true
	for name in ["fixtures", "table", "calendar", "interest", "stats", "system"]:
		var image := Image.new()
		assert_eq(image.load("res://assets/ui/league/%s.png" % name), OK, "%s icon did not load" % name)
		assert_eq(image.get_format(), Image.FORMAT_RGBA8, "%s icon is not RGBA" % name)
		assert_true(image.get_pixel(0, 0).a < 0.5, "%s icon has an opaque corner" % name)

# --------------------------------------------------------------- interest ---

func test_the_interest_list_searches_adds_and_removes() -> void:
	new_season()
	press_nav("nav:interest")
	assert_eq(screen().mode, "interest", "the panel did not open Teams of Interest")
	var note := false
	for item in screen().buttons:
		if str(item["kind"]) == "note":
			note = true
	assert_true(note, "an empty shortlist has no empty state")
	for code in [KEY_A, KEY_R, KEY_S]:
		assert_true(screen().key(code), "the search field ignored a letter")
	var results: Array = screen().current_view()["results"]
	assert_false(results.is_empty(), "the search found no club")
	press_id("interest:add:ARS")
	assert_true((LeagueSeason.active.state()["interests"] as Array).has("ARS"),
		"the search did not mark the club")
	assert_eq(str(screen().interest_query), "", "adding a club kept the query")
	press_id("interest:remove:ARS")
	assert_false((LeagueSeason.active.state()["interests"] as Array).has("ARS"),
		"the remove chip did not unmark")
	press_id("back")
	assert_eq(screen().mode, "hub", "Back did not leave the list")

func test_a_followed_club_reads_watch_on_the_planner() -> void:
	new_season()
	var plan: Array = screen().current_view()["plan"]
	var fixture: Dictionary = plan[0]
	var club := str(fixture["home_club_id"])
	LeagueSeason.active.set_interest(club, true)
	screen().refresh()
	for item in screen().current_view()["plan"]:
		if str(item["home_club_id"]) == club or str(item["away_club_id"]) == club:
			assert_true(bool(item["watch"]), "a followed club's fixture reads Auto")
	LeagueSeason.active.set_interest(club, false)
	screen().refresh()

# ------------------------------------------------------------------- stats ---

func test_stats_lists_reports_and_the_podium_when_available() -> void:
	new_season()
	press_nav("nav:stats")
	assert_eq(screen().mode, "stats", "the panel did not open Stats")
	var note := false
	for item in screen().buttons:
		if str(item["kind"]) == "note":
			note = true
	assert_true(note, "Stats with no played day has no empty state")
	LeagueSeason.active.advance()
	screen().refresh()
	var day := ""
	for item in screen().buttons:
		if str(item["kind"]) == "day":
			day = str(item["id"])
	assert_true(day != "", "Stats did not list the played matchday")
	press_id(day)
	assert_eq(screen().mode, "report", "a Stats matchday did not open its roundup")
	assert_false(screen().roundup.is_empty(), "the roundup is empty")
	assert_eq(str(screen().report_back), "stats", "the report forgot it came from Stats")
	press_id("back")
	assert_eq(screen().mode, "stats", "Back did not return to Stats")
	PLDatabase.execute("UPDATE league_fixture SET home_goals = 1, away_goals = 0, status = 'played';")
	LeagueSeason.active.record.standings.recompute()
	LeagueSeason.active.save.set_status("complete")
	LeagueSeason.active.save.reload()
	press_nav("nav:stats")
	var podium_door := false
	for item in screen().buttons:
		if str(item["id"]) == "stats:podium":
			podium_door = true
	assert_true(podium_door, "a complete season's Stats has no Podium door")
	press_id("stats:podium")
	assert_eq(screen().mode, "podium", "the Stats Podium door did not open")

func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
