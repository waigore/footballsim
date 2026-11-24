extends GdToolsTest

## The left panel, Teams of Interest, Stats and System driven through the real
## scene: the hub without its bottom door bar, panel navigation, long-press on a
## team name, search/add/remove, the Stats reports and podium, and a Load that
## fully unloads the season that was in memory.

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
			game.menus.league.unload_season()
			game.menus.league.close()
		game.queue_free()
		# A freed scene must actually leave the tree before the next suite runs:
		# a live one holds the share of file handles the editor opened.
		await get_tree().process_frame
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	LeagueInterest.current = null
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func screen():
	return game.menus.league.screen

func vp() -> Vector2:
	return screen().design_vp()

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

func press_id(id: String) -> void:
	for item in screen().buttons:
		if str(item["id"]) == id:
			press((item["rect"] as Rect2).get_center())
			return
	assert_true(false, "no button %s on screen %s" % [id, screen().mode])

func press_point(r: Rect2) -> void:
	press(r.get_center())

func open_panel() -> void:
	if screen().panel.target < 0.5:
		screen().panel.open()
	screen().panel.settle()
	screen().refresh()

## Press a panel row and settle the slide: a panel that is still sliding out
## covers the sheet until it finishes, exactly as it does for a player.
func press_nav(id: String) -> void:
	open_panel()
	for i in range(LeaguePanel.ITEMS.size()):
		if str(LeaguePanel.ITEMS[i]["id"]) == id:
			press_point(screen().panel.item_rect(vp(), i))
			screen().panel.settle()
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
	for item in screen().buttons:
		ids.append(str(item["id"]))
	for gone in ["table", "calendar", "menu"]:
		assert_false(ids.has(gone), "the hub still carries the %s door" % gone)
	assert_true(ids.has("continue"), "the hub lost CONTINUE")
	assert_true(ids.has("back"), "the hub lost BACK")
	var back: Rect2 = Rect2()
	var cont: Rect2 = Rect2()
	for item in screen().buttons:
		if str(item["id"]) == "back":
			back = item["rect"]
		if str(item["id"]) == "continue":
			cont = item["rect"]
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
	assert_false(screen().panel.is_open(), "the panel opened by itself")
	press_point(screen().panel.tab_rect(vp()))
	assert_true(screen().panel.is_open(), "the panel did not open")
	screen().panel.update(0.5)
	assert_almost_eq(screen().panel.slide, 1.0, 0.01, "the panel did not settle open")
	# A row's hit target travels with the slide: the geometry is the paint.
	var row: Rect2 = screen().panel.item_rect(vp(), 0)
	assert_true(row.position.x > 0.0, "the panel rows did not slide in with the panel")
	press_nav("nav:table")
	assert_eq(screen().mode, "table", "the panel did not open the table")
	assert_false(screen().panel.is_open(), "the panel stayed open over the table")
	open_panel()
	press_nav("nav:calendar")
	assert_eq(screen().mode, "calendar", "the panel did not open the calendar")
	open_panel()
	press_nav("nav:fixtures")
	assert_eq(screen().mode, "hub", "Today's Fixtures did not come back")
	# A scrim press closes the panel and leaves the sheet where it was.
	open_panel()
	press(Vector2(vp().x - 30.0, vp().y * 0.5))
	screen().panel.settle()
	assert_false(screen().panel.is_open(), "a press beside the panel did not close it")
	assert_eq(screen().mode, "hub", "closing the panel changed the sheet")

func test_every_panel_destination_opens_and_draws() -> void:
	new_season()
	for pair in [["nav:table", "table"], ["nav:calendar", "calendar"], ["nav:interest", "interest"],
			["nav:stats", "stats"], ["nav:system", "system"], ["nav:fixtures", "hub"]]:
		press_nav(str(pair[0]))
		assert_eq(screen().mode, str(pair[1]), "the panel did not open %s" % pair[1])
		screen().queue_redraw()
		await get_tree().process_frame
	press_id("back")

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
	assert_eq(str(screen().current_view()["query"]), "ars", "the query did not reach the field")
	var results: Array = screen().current_view()["results"]
	assert_false(results.is_empty(), "the search found no club")
	var found := ""
	for club in results:
		if str(club["abbr"]) == "ARS":
			found = str(club["id"])
	assert_eq(found, "ARS", "the search did not find Arsenal")
	press_id("interest:add:ARS")
	assert_true(LeagueSeason.active.interest.has("ARS"), "the search did not mark the club")
	assert_eq(str(screen().current_view()["query"]), "", "adding a club kept the query")
	var listed := false
	for item in screen().buttons:
		if str(item["id"]) == "club:ARS":
			listed = true
	assert_true(listed, "the marked club is not on the list")
	press_id("interest:remove:ARS")
	assert_false(LeagueSeason.active.interest.has("ARS"), "the remove chip did not unmark")
	press_id("back")
	assert_eq(screen().mode, "hub", "Back did not leave the list")

func test_a_marked_club_reads_watch_on_the_planner() -> void:
	new_season()
	var fixture: Dictionary = screen().current_view()["plan"][0]
	var club := str(fixture["home_club_id"])
	LeagueSeason.active.interest.set_interest(club, true)
	screen().refresh()
	var plan: Array = screen().current_view()["plan"]
	for item in plan:
		if str(item["home_club_id"]) == club or str(item["away_club_id"]) == club:
			assert_true(bool(item["watch"]), "a marked club's fixture reads Auto")
	assert_eq(int(LeagueSeason.active.record.fixture(str(fixture["id"]))["watched"]), 1,
		"the mark did not reach the ledger")
	LeagueSeason.active.interest.set_interest(club, false)
	LeagueSeason.active.set_watch(str(fixture["id"]), false)
	screen().refresh()

func test_a_long_press_on_a_team_name_opens_the_context_menu() -> void:
	new_season()
	var plan: Array = screen().current_view()["plan"]
	var fixture: Dictionary = plan[0]
	var home := str(fixture["home_club_id"])
	var row := Rect2()
	for item in screen().buttons:
		if str(item["id"]) == "fixture:" + str(fixture["id"]):
			row = item["rect"]
	assert_true(row.size.x > 0.0, "the fixture row is not on the sheet")
	var host = game.menus.league
	host.hold_ms = 0
	press(Vector2(row.position.x + 80.0, row.position.y + 13.0))
	assert_true(screen().menu.open, "a hold did not raise the context menu")
	assert_eq(screen().menu.club_id, home, "the hold found the wrong club")
	press_point(screen().menu.action_rect(vp()))
	assert_true(LeagueSeason.active.interest.has(home), "the menu did not mark the club")
	assert_false(screen().menu.open, "the menu stayed after its action")
	assert_true(LeagueInterest.marked(home), "the club does not read marked for the paint")
	# Put the fixture back to Auto before the tap check: a short tap on a watched
	# fixture starts the viewer, which is not what this case is asking about.
	LeagueSeason.active.interest.set_interest(home, false)
	LeagueSeason.active.set_watch(str(fixture["id"]), false)
	screen().refresh()
	host.hold_ms = 10000
	press(Vector2(row.position.x + 80.0, row.position.y + 13.0))
	assert_false(screen().menu.open, "a short tap raised the context menu")
	assert_eq(screen().mode, "hub", "a short tap left the planner")
	host.hold_ms = InterestMenu.HOLD_MS
	LeagueSeason.active.set_watch(str(fixture["id"]), false)
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
	press_id("back")
	PLDatabase.execute("UPDATE league_fixture SET home_goals = 1, away_goals = 0, status = 'played';")
	LeagueSeason.active.record.recompute_table()
	LeagueSeason.active.save.set_status("complete")
	LeagueSeason.active.save.reload()
	screen().refresh()
	press_nav("nav:stats")
	var podium_door := false
	for item in screen().buttons:
		if str(item["id"]) == "stats:podium":
			podium_door = true
	assert_true(podium_door, "a complete season's Stats has no Podium door")
	press_id("stats:podium")
	assert_eq(screen().mode, "podium", "the Stats Podium door did not open")
	press_id("back")

# ------------------------------------------------------------------ system ---

func test_the_system_row_opens_the_seasons_own_sheet() -> void:
	new_season()
	press_nav("nav:system")
	assert_eq(screen().mode, LeagueScreen.MODE_SYSTEM, "the panel did not open System")
	var ids: Array = []
	for item in screen().buttons:
		ids.append(str(item["id"]))
	for id in ["sys:quick", "sys:save", "sys:load", "sys:menu", "sys:quit"]:
		assert_true(ids.has(id), "System is missing %s" % id)
	press_id("back")
	assert_eq(screen().mode, "hub", "BACK did not leave System")

func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))
