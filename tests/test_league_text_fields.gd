extends GdToolsTest

## Typing into the season's painted text fields (#201). A phone has no keyboard,
## and these three fields are painted strings rather than LineEdits, so nothing
## raised the platform's keyboard: a touch-only player could not rename a save.
## The suite drives the screen the way the pointer does — press the field, type
## the characters a soft keyboard sends — and checks the keyboard is asked for
## once, points at the field the player pressed, and is put away again.

const SAVE_DIR := "user://saves_test_text_fields_201"
const CACHE_DIR := "user://cache_test_text_fields_201"

var game = null
## One generated season shared by the SAVE AS / shortlist keyboard tests so
## coverage does not rebuild three calendars for the same chrome.
var season: LeagueSeason = null
## Fields the fake keyboard was asked for, in order: `{text, frame, max_length}`,
## and how many times it was put away. A lambda captures a local by value in
## GDScript, so the counter lives in a one-cell array the closure can write.
var asked: Array = []
var hidden := [0]
## Whether the fake platform reports its keyboard as up, so a press can be told
## from a repaint.
var keyboard_up := [false]

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	# Record what the sheet asks of the platform. A headless run has no
	# on-screen keyboard at all, which is exactly the desktop case the sheet must
	# survive, so the seam is stubbed here rather than left implicit.
	asked.clear()
	hidden[0] = 0
	keyboard_up[0] = false
	SoftKeyboard.on_show = func(text: String, frame: Rect2, max_length: int) -> void:
		asked.append({"text": text, "frame": frame, "max_length": max_length})
		keyboard_up[0] = true
	SoftKeyboard.on_hide = func() -> void:
		hidden[0] += 1
		keyboard_up[0] = false
	SoftKeyboard.on_shown = func() -> bool:
		return keyboard_up[0]
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.open_menu()
	season = LeagueSeason.create("Keyboard Season", "generated", "fixture_days", 0)

func after_all() -> void:
	SoftKeyboard.on_show = Callable()
	SoftKeyboard.on_hide = Callable()
	SoftKeyboard.on_shown = Callable()
	if game != null:
		if game.menus.league != null:
			game.menus.league.close()
		game.queue_free()
	if season != null:
		season.close()
		season = null
	LeagueSeason.active = null
	LeagueSave.close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func screen():
	return game.menus.league.screen

## The season's other readings live in the left panel (#105): their door ids are
## the panel rows, which the screen dispatches like any other door.
const PANEL_DOORS := {"system": "nav:system", "interest": "nav:interest",
	"table": "nav:table", "calendar": "nav:calendar", "stats": "nav:stats"}

func press_id(id: String) -> void:
	var wanted: String = str(PANEL_DOORS.get(id, id))
	for item in screen().buttons:
		if str(item["id"]) == wanted:
			screen().click(wanted)
			return
	if PANEL_DOORS.values().has(wanted):
		screen().click(wanted)
		return
	assert_true(false, "no button %s on %s" % [wanted, screen().mode])

func _clean() -> void:
	for suffix in ["", "-wal", "-shm"]:
		var path: String = SAVE_DIR + "/" + "x" + suffix
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	var dir := DirAccess.open(SAVE_DIR)
	if dir != null:
		for name in dir.get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_DIR + "/" + name))
	if DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(CACHE_DIR)):
		for name in DirAccess.open(CACHE_DIR).get_files():
			DirAccess.remove_absolute(ProjectSettings.globalize_path(CACHE_DIR + "/" + name))

# ---------------------------------------------------------------- wizard ---

func test_pressing_the_wizard_name_asks_for_the_keyboard_on_that_field() -> void:
	asked.clear()
	game.menus.league.open_wizard()
	var field := LeagueFieldFocus.field_rect(screen(), LeagueFieldFocus.WIZARD)
	assert_gt(field.size.y, 0.0, "the wizard painted no name field")
	press_id("name")
	assert_eq(asked.size(), 1, "pressing the name field did not ask for a keyboard")
	assert_eq(str(screen().focus.kind), LeagueFieldFocus.WIZARD, "the field did not take focus")
	assert_eq(str(asked[0]["text"]), str(screen().wizard["name"]),
		"the keyboard did not open on the name the field holds")
	assert_almost_eq((asked[0]["frame"] as Rect2).position.x, field.position.x * screen().ui_scale, 0.5,
		"the keyboard points at a different box than the one pressed")
	screen().close()

func test_a_repaint_leaves_the_keyboard_alone_but_a_fresh_press_raises_it() -> void:
	game.menus.league.open_wizard()
	asked.clear()
	press_id("name")
	assert_eq(asked.size(), 1, "the field did not take the keyboard")
	# A repaint (a key landing in the field, a resize) must not restart the IME.
	screen().text_key(0, "q".unicode_at(0))
	screen().refresh()
	assert_eq(asked.size(), 1, "a repaint restarted the keyboard under the player's hands")
	# The player put the keyboard away themselves (Android's back key does that
	# without telling the game): pressing the field brings it back.
	keyboard_up[0] = false
	press_id("name")
	assert_eq(asked.size(), 2, "a field pressed again did not raise the keyboard again")
	screen().close()

func test_the_keyboard_is_put_away_by_another_press_and_by_back() -> void:
	game.menus.league.open_wizard()
	press_id("name")
	hidden[0] = 0
	press_id("mode:real")
	assert_eq(hidden[0], 1, "pressing another door left the keyboard up")
	assert_eq(str(screen().focus.kind), "", "the field kept the keyboard after another press")
	press_id("name")
	hidden[0] = 0
	screen().key(KEY_ESCAPE)
	assert_gte(hidden[0], 1, "BACK left the keyboard up")
	assert_eq(str(screen().focus.kind), "", "BACK did not release the field")

func test_a_soft_keyboards_characters_reach_the_name() -> void:
	game.menus.league.open_wizard()
	screen().wizard["name"] = ""
	press_id("name")
	# What a soft keyboard sends: a character with no keycode of its own.
	for ch in ["h", "e", "r", "o", "e", "s"]:
		assert_true(screen().text_key(0, ch.unicode_at(0)), "the field refused the character '%s'" % ch)
	assert_eq(str(screen().wizard["name"]), "Heroes", "the typed characters did not reach the name")
	# A digit, a space and the length cap all follow the same grammar.
	screen().text_key(0, "2".unicode_at(0))
	screen().text_key(0, " ".unicode_at(0))
	screen().text_key(0, "x".unicode_at(0))
	assert_eq(str(screen().wizard["name"]), "Heroes2 x", "a digit or the space broke the name")
	for i in range(40):
		screen().text_key(0, "y".unicode_at(0))
	assert_lte(str(screen().wizard["name"]).length(), LeagueTextField.MAX_CHARS,
		"the name grew past the field's limit")
	screen().close()

func test_a_physical_key_still_types_the_letter_printed_on_it() -> void:
	game.menus.league.open_wizard()
	screen().wizard["name"] = ""
	# A physical key names its letter with a keycode; the character path must not
	# double it.
	var ev := InputEventKey.new()
	ev.keycode = KEY_A
	ev.unicode = "A".unicode_at(0)
	ev.pressed = true
	assert_true(screen().text_key(ev.keycode, ev.unicode) == false,
		"the physical key was taken twice")
	screen().key(KEY_A)
	assert_eq(str(screen().wizard["name"]), "A", "the physical key did not reach the name")
	screen().close()

# ---------------------------------------------------------------- system ---

func test_save_as_opens_the_keyboard_and_takes_a_typed_name() -> void:
	assert_not_null(season, "the shared season was not created")
	game.menus.league.show_season(season)
	press_id("system")
	asked.clear()
	press_id("sys:save")
	assert_true(bool(screen().sys["naming"]), "SAVE AS did not open its field")
	assert_eq(asked.size(), 1, "SAVE AS did not ask for the keyboard")
	assert_eq(str(asked[0]["text"]), str(screen().sys["name"]),
		"the keyboard did not open on the suggested name")
	for ch in ["o", "k"]:
		screen().text_key(0, ch.unicode_at(0))
	assert_true(str(screen().sys["name"]).to_lower().ends_with("ok"),
		"the typed characters did not reach the field")
	# CANCEL is a press that is not the field: the keyboard goes with the field.
	hidden[0] = 0
	press_id("sys:cancel")
	assert_false(bool(screen().sys["naming"]), "CANCEL left the field open")
	assert_gte(hidden[0], 1, "the keyboard stayed up over a sheet with no field")
	screen().close()

func test_committing_save_as_shuts_the_keyboard() -> void:
	assert_not_null(season, "the shared season was not created")
	game.menus.league.show_season(season)
	press_id("system")
	press_id("sys:save")
	hidden[0] = 0
	press_id("sys:commit")
	assert_false(bool(screen().sys["naming"]), "SAVE left the field open")
	assert_gte(hidden[0], 1, "the keyboard stayed up after the copy was written")
	assert_eq(str(screen().focus.kind), "", "the field kept focus after the copy was written")
	screen().close()

# -------------------------------------------------------------- interest ---

func test_the_shortlist_search_raises_its_keyboard_and_takes_text() -> void:
	assert_not_null(season, "the shared season was not created")
	game.menus.league.show_season(season)
	press_id("interest")
	asked.clear()
	press_id("interest:search")
	assert_eq(asked.size(), 1, "the search field did not ask for the keyboard")
	# The search is a filter, so its own characters are lower case.
	screen().text_key(0, "L".unicode_at(0))
	screen().text_key(0, "I".unicode_at(0))
	assert_eq(str(screen().interest_query), "li", "the typed characters did not reach the search")
	assert_eq(str(screen().focus.kind), LeagueFieldFocus.INTEREST, "the search did not take focus")
	screen().close()
