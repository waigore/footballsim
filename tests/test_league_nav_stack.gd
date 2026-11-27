extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_league_nav")
var CACHE_DIR := TestScratch.dir("cache_test_league_nav")
const SEED := 977

var season: LeagueSeason = null
var screen: LeagueScreen = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Nav Season", "generated", "fixture_days", SEED)
	screen = LeagueScreen.new()
	add_child(screen)
	screen.season = season
	screen.mode = LeagueScreen.MODE_HUB

func after_all() -> void:
	if screen != null:
		screen.queue_free()
		screen = null
	if season != null:
		season.close()
		season = null
	LeagueSeason.active = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)


func _root() -> void:
	screen.season = season
	screen.nav.clear()
	screen.mode = LeagueScreen.MODE_HUB
	screen.refresh()

func test_the_stack_keeps_thirty_pages_and_drops_the_oldest() -> void:
	var stack := LeagueNavStack.new()
	assert_true(stack.is_empty(), "a new stack is not empty")
	for i in range(35):
		stack.push({"page": i})
	assert_eq(stack.depth(), LeagueNavStack.CAPACITY, "the stack grew past its cap")
	var first := stack.pop()
	assert_eq(int(first.get("page", -1)), 34, "the newest page was not on top")
	var oldest := -1
	while not stack.is_empty():
		oldest = int(stack.pop().get("page", -1))
	assert_eq(oldest, 5, "the oldest page was kept instead of dropped")
	assert_true(stack.pop().is_empty(), "an empty stack popped a page")

func test_back_at_the_root_is_disabled_and_never_leaves_the_season() -> void:
	_root()
	for code in [KEY_ESCAPE, KEY_BACKSPACE]:
		assert_true(screen.key(code), "a back key was not taken at the root")
		assert_eq(screen.mode, LeagueScreen.MODE_HUB, "a back key moved the root")
		assert_true(screen.visible, "a back key left the season")
	var door := {}
	for item in screen.buttons:
		if str(item["id"]) == "back":
			door = item
	assert_false(door.is_empty(), "the root has no BACK door")
	assert_true(bool(door.get("disabled", false)), "the root BACK door is not disabled")
	screen.click("back")
	assert_true(screen.visible, "pressing the disabled BACK door left the season")

func test_a_panel_jump_pushes_a_page_and_back_undoes_it() -> void:
	_root()
	screen.click("table")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "the table did not open")
	assert_eq(screen.nav.depth(), 1, "the table did not leave a page behind")

	screen.click("calendar")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "the calendar did not open")
	assert_eq(screen.nav.depth(), 2, "the calendar did not leave a page behind")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_TABLE, "BACK did not return to the table")
	assert_eq(screen.nav.depth(), 1, "BACK did not pop one page")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "BACK did not return to the hub")
	assert_eq(screen.nav.depth(), 0, "the root still holds a page")

func test_the_calendar_day_and_stats_are_pages_of_their_own() -> void:
	_root()
	screen.click("calendar")
	var date := ""
	for item in screen.buttons:
		if str(item["kind"]) == "cell" and int((item["info"] as Dictionary).get("n", 0)) > 0:
			date = str(item["date"])
			break
	assert_true(date != "", "the calendar lists no fixture day")
	screen.click("day:" + date)
	assert_eq(screen.day, date, "the day did not open")
	screen.panel.open()
	screen.panel.settle()
	screen.click("nav:stats")
	assert_eq(screen.mode, LeagueScreen.MODE_STATS, "Stats did not open")

	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "BACK did not return to the calendar")
	assert_eq(screen.day, date, "the calendar forgot its day")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "the calendar's page was lost")

func test_a_report_returns_to_the_page_that_opened_it() -> void:
	_root()
	var played := ""
	for row in season.record.fixtures.all():
		if str(row["status"]) == "played":
			played = str(row["id"])
			break
	if played == "":
		season.advance()
		for row in season.record.fixtures.all():
			if str(row["status"]) == "played":
				played = str(row["id"])
				break
	assert_true(played != "", "there is no played fixture to open")

	screen.mode = LeagueScreen.MODE_STATS
	screen.nav.clear()
	screen.refresh()
	var day := ""
	for item in screen.buttons:
		if str(item["id"]).begins_with("statsday:"):
			day = str(item["id"])
			break
	assert_true(day != "", "Stats listed no played matchday")
	screen.click(day)
	assert_eq(screen.mode, LeagueScreen.MODE_REPORT, "a matchday did not open its roundup")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_STATS, "BACK did not return to Stats")

	screen.mode = LeagueScreen.MODE_HUB
	screen.nav.clear()
	screen.show_report(played)
	assert_eq(screen.mode, LeagueScreen.MODE_REPORT, "the report did not open")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "BACK did not return to the hub")

func test_the_system_sheet_returns_to_the_page_it_covered() -> void:
	_root()
	screen.click("calendar")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "the calendar did not open")
	screen.click("system")
	assert_eq(screen.mode, LeagueScreen.MODE_SYSTEM, "System did not open over the calendar")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR,
		"BACK from System did not return to the page it covered")

	screen.click("system")
	screen.click("sys:load")
	assert_eq(screen.mode, LeagueScreen.MODE_LOAD, "Load did not open over the season")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_SYSTEM, "BACK from Load did not return to System")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_CALENDAR, "BACK from System lost the calendar")

func test_main_menu_leaves_the_season_and_clears_the_history() -> void:
	_root()
	screen.click("table")
	assert_eq(screen.nav.depth(), 1, "the table left no page")
	screen.click("back")
	screen.click("system")
	screen.click("sys:menu")
	assert_false(screen.visible, "MAIN MENU left the season on screen")
	assert_eq(screen.nav.depth(), 0, "MAIN MENU kept the season's history")

func test_the_history_is_session_state_and_is_never_saved() -> void:
	_root()
	screen.click("table")
	screen.click("calendar")
	assert_gte(screen.nav.depth(), 2, "the season kept no history to lose")

	season.save.touch()
	assert_false(str(season.save.read_meta()).contains("nav"),
		"the page history was written into the save")

	screen.close()
	assert_eq(screen.nav.depth(), 0, "closing the season kept its history")
	screen.open_season(season)
	assert_eq(screen.nav.depth(), 0, "a reopened season remembered a page")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "a reopened season did not land on its hub")
