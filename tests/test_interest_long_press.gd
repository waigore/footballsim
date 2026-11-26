extends GdToolsTest

## A long press on a club name (#107): the same gesture on every surface raises
## the Teams of Interest menu, a short tap still does what it always did, a drag
## never opens it, and the one write it makes is the season's shortlist.
##
## The grammar, the menu and the strip registry are pure, so most of this suite
## drives them directly; the league sheet, the picker and the encyclopedia are
## driven through their real screens, because "which club is under the finger" is
## a question only the painter can answer.

var SAVE_DIR := TestScratch.dir("saves_test_long_press")
var CACHE_DIR := TestScratch.dir("cache_test_long_press")
const SEED := 2031

var season: LeagueSeason = null

# ------------------------------------------------------------------ fakes ---

class FakeInterest extends RefCounted:
	var marked := {}

	func is_interested(club_id: String) -> bool:
		return marked.has(club_id)

	func interests() -> Array:
		return marked.keys()

class FakeRecord extends RefCounted:
	var interest := FakeInterest.new()

class FakeSeason extends RefCounted:
	var record := FakeRecord.new()
	var writes: Array = []

	func set_interest(club_id: String, wanted: bool) -> void:
		writes.append([club_id, wanted])
		if wanted:
			record.interest.marked[club_id] = true
		else:
			record.interest.marked.erase(club_id)

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func before_each() -> void:
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func after_each() -> void:
	if season != null:
		season.close()
		season = null
	LeagueSeason.active = null

func after_all() -> void:
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	for folder in [SAVE_DIR, CACHE_DIR]:
		TestScratch.clear(folder)

func _down(p: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = p
	return ev

func _up(p: Vector2) -> InputEventMouseButton:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = false
	ev.position = p
	return ev

func _motion(p: Vector2) -> InputEventMouseMotion:
	var ev := InputEventMouseMotion.new()
	ev.position = p
	return ev

## A hold wired to a fake season: no save, no repository, just the grammar.
func _hold(season_in) -> InterestHold:
	var hold := InterestHold.new()
	hold.vp = Vector2(1280, 800)
	hold.club_at = func(p: Vector2) -> String:
		return "MUN" if p.x < 100.0 else ("MCI" if p.x < 200.0 else "")
	hold.season_of = func(): return season_in
	return hold

# --------------------------------------------------------------- the press ---

func test_a_short_tap_is_still_a_click() -> void:
	var press := InterestPress.new()
	press.press(Vector2(10, 10), "MUN")
	assert_true(press.armed(), "the press did not arm on a club name")
	assert_true(press.release_click(), "a short tap on a name stopped being a click")

func test_the_hold_fires_once_after_its_clock() -> void:
	var press := InterestPress.new()
	press.press(Vector2(10, 10), "MUN")
	assert_false(press.tick(InterestPress.HOLD * 0.5), "the hold fired too early")
	assert_true(press.tick(InterestPress.HOLD * 0.5 + 0.01), "the hold never fired")
	assert_false(press.tick(0.5), "the hold fired twice for one press")
	assert_false(press.release_click(), "a fired hold still ran a click")

func test_a_drag_cancels_the_hold() -> void:
	var press := InterestPress.new()
	press.press(Vector2(10, 10), "MUN")
	press.move(Vector2(10 + InterestPress.SLOP + 2.0, 10))
	assert_false(press.armed(), "travel past the slop left the hold armed")
	assert_false(press.tick(1.0), "a drag still opened the menu")
	assert_false(press.release_click(), "a drag's release ran a click")

func test_shaky_travel_below_the_slop_still_holds() -> void:
	var press := InterestPress.new()
	press.press(Vector2(10, 10), "MUN")
	press.move(Vector2(12, 12))
	assert_true(press.armed(), "a shaky hand cancelled the hold")
	assert_true(press.tick(InterestPress.HOLD + 0.01), "the hold never fired")

func test_a_press_on_plain_chrome_never_holds() -> void:
	var press := InterestPress.new()
	press.press(Vector2(10, 10), "")
	assert_false(press.armed(), "an empty name armed the hold")
	assert_false(press.tick(2.0), "chrome opened the menu")
	assert_true(press.release_click(), "chrome's click was swallowed")

# ---------------------------------------------------------------- the menu ---

func test_the_menu_stays_inside_the_sheet() -> void:
	var menu := InterestMenu.new()
	menu.show("MUN", "Manchester United", "MUN", false, Vector2(1270, 790))
	var vp := Vector2(1280, 800)
	var r := menu.rect(vp)
	assert_true(r.position.x >= InterestMenu.EDGE - 0.01, "the card hung off the left")
	assert_true(r.end.x <= vp.x - InterestMenu.EDGE + 0.01, "the card hung off the right")
	assert_true(r.end.y <= vp.y - InterestMenu.EDGE + 0.01, "the card hung off the bottom")

func test_the_door_says_what_a_press_does() -> void:
	var menu := InterestMenu.new()
	menu.show("MUN", "Manchester United", "MUN", false, Vector2(400, 300))
	assert_true(menu.door_label().contains("FOLLOW MUN"), "an unfollowed club's door did not offer the follow")
	menu.show("MUN", "Manchester United", "MUN", true, Vector2(400, 300))
	assert_true(menu.door_label().contains("STOP FOLLOWING"), "a followed club's door did not offer the release")

func test_every_press_is_answered_by_the_open_menu() -> void:
	var menu := InterestMenu.new()
	menu.show("MUN", "Manchester United", "MUN", false, Vector2(400, 300))
	var vp := Vector2(1280, 800)
	assert_eq(menu.hit(menu.door_rect(vp).get_center(), vp), InterestMenu.TOGGLE, "the door was not a toggle")
	assert_eq(menu.hit(menu.close_rect(vp).get_center(), vp), InterestMenu.CLOSE, "the ✕ was not a close")
	assert_eq(menu.hit(Vector2(4, 4), vp), InterestMenu.DISMISS, "a press beside the card was not a dismiss")
	menu.close()
	assert_eq(menu.hit(menu.door_rect(vp).get_center(), vp), "", "a closed menu answered a press")

# -------------------------------------------------------------- the strips ---

func test_strips_name_the_club_under_a_point() -> void:
	var names := InterestNames.new()
	names.add(Rect2(10, 10, 40, 20), "MUN")
	names.add(Rect2(60, 10, 40, 20), "MCI")
	assert_eq(names.at(Vector2(20, 15)), "MUN", "the home strip lost its club")
	assert_eq(names.at(Vector2(70, 15)), "MCI", "the away strip lost its club")
	assert_eq(names.at(Vector2(200, 15)), "", "a bare point named a club")
	names.clear()
	assert_eq(names.at(Vector2(20, 15)), "", "a cleared registry still named a club")

func test_the_same_strip_is_registered_once() -> void:
	var names := InterestNames.new()
	names.add(Rect2(10, 10, 40, 20), "MUN")
	names.add(Rect2(10, 10, 40, 20), "MUN")
	assert_eq(names.zones.size(), 1, "a repaint that moved nothing grew the list")
	names.add(Rect2(10, 10, 40, 20), "")
	assert_eq(names.zones.size(), 1, "an empty club id was registered")

func test_the_strip_matches_the_caption_it_painted() -> void:
	var font: Font = UiChrome.fonts()["bold"]
	var strip: Rect2 = InterestNames.strip(font, "MUN", 60.0, 100.0, 13)
	assert_almost_eq(strip.position.x, 60.0, 0.01)
	assert_true(strip.size.x >= 12.0, "a short abbreviation lost its tap target")
	assert_true(strip.has_point(Vector2(62.0, 98.0)), "the strip missed the glyphs it painted")

# ---------------------------------------------------------------- the hold ---

func test_a_hold_opens_the_menu_for_the_named_club() -> void:
	var fake := FakeSeason.new()
	var hold := _hold(fake)
	assert_true(hold.press_at(Vector2(50, 40)), "a press on a name was not watched")
	assert_true(hold.tick(InterestPress.HOLD + 0.01), "the hold never opened the menu")
	assert_true(hold.is_open(), "no menu after the hold")
	assert_eq(hold.menu.club_id, "MUN", "the menu named the wrong club")
	assert_eq(hold.menu.abbr, "MUN", "the menu lost the club's abbreviation")

func test_the_release_that_opened_the_menu_does_not_dismiss_it() -> void:
	var fake := FakeSeason.new()
	var hold := _hold(fake)
	hold.press_at(Vector2(50, 40))
	hold.tick(InterestPress.HOLD + 0.01)
	assert_true(hold.release_at(Vector2(50, 40)), "the opening release was not consumed")
	assert_true(hold.is_open(), "the menu closed on the release that raised it")

func test_the_door_writes_the_shortlist() -> void:
	var fake := FakeSeason.new()
	var hold := _hold(fake)
	hold.press_at(Vector2(50, 40))
	hold.tick(InterestPress.HOLD + 0.01)
	assert_true(hold.click(InterestMenu.TOGGLE), "the door was not consumed")
	assert_eq(fake.writes.size(), 1, "the door did not write once")
	assert_eq(fake.writes[0], ["MUN", true], "the door followed the wrong club")
	assert_false(hold.is_open(), "the menu stayed up after the write")

func test_a_press_beside_the_card_dismisses_without_a_write() -> void:
	var fake := FakeSeason.new()
	var hold := _hold(fake)
	hold.press_at(Vector2(50, 40))
	hold.tick(InterestPress.HOLD + 0.01)
	hold.release_at(Vector2(50, 40))
	# Beside the card: a second press, answered by the menu rather than the sheet.
	assert_true(hold.press_at(Vector2(2, 2)), "a press beside the card was not taken")
	assert_true(hold.release_at(Vector2(2, 2)), "a press beside the card was not consumed")
	assert_false(hold.is_open(), "the menu stayed up")
	assert_true(fake.writes.is_empty(), "a dismiss wrote the shortlist")

func test_with_no_season_there_is_no_menu() -> void:
	var hold := _hold(null)
	assert_false(hold.press_at(Vector2(50, 40)), "a name was watched with no season open")
	assert_false(hold.tick(InterestPress.HOLD + 0.01), "a hold opened a menu with no season")
	assert_false(hold.is_open(), "a menu appeared with no season")

# ----------------------------------------------------- the shared pointer ---

class PointerSheet extends RefCounted:
	var mouse := Vector2(-1000, -1000)
	var holding := false
	var touch := true
	var id := "fixture:1"
	var clicks: Array = []
	var scrolls: Array = []

	func button_at(_p: Vector2) -> String:
		return id

	func click(pressed: String) -> void:
		clicks.append(pressed)

	func scroll_by(dy: float, dx: float = 0.0) -> void:
		scrolls.append(Vector2(dx, dy))

func test_a_hold_under_the_pointer_swallows_the_click() -> void:
	var fake := FakeSeason.new()
	var sheet := PointerSheet.new()
	var pointer := SheetPointer.new(sheet)
	pointer.hold = _hold(fake)
	pointer.handle(_down(Vector2(50, 40)), Vector2(50, 40))
	pointer.hold.tick(InterestPress.HOLD + 0.01)
	pointer.handle(_up(Vector2(50, 40)), Vector2(50, 40))
	assert_true(pointer.hold.is_open(), "the pointer's hold did not open the menu")
	assert_true(sheet.clicks.is_empty(), "a fired hold still clicked the row underneath")

func test_a_short_tap_under_the_pointer_still_clicks() -> void:
	var fake := FakeSeason.new()
	var sheet := PointerSheet.new()
	var pointer := SheetPointer.new(sheet)
	pointer.hold = _hold(fake)
	pointer.handle(_down(Vector2(50, 40)), Vector2(50, 40))
	pointer.handle(_up(Vector2(50, 40)), Vector2(50, 40))
	assert_false(pointer.hold.is_open(), "a short tap opened the menu")
	assert_eq(sheet.clicks, ["fixture:1"], "a short tap lost its click")

func test_a_drag_under_the_pointer_scrolls_instead_of_holding() -> void:
	var fake := FakeSeason.new()
	var sheet := PointerSheet.new()
	var pointer := SheetPointer.new(sheet)
	pointer.hold = _hold(fake)
	pointer.handle(_down(Vector2(50, 40)), Vector2(50, 40))
	pointer.handle(_motion(Vector2(50, 140)), Vector2(50, 140))
	pointer.hold.tick(InterestPress.HOLD + 0.01)
	pointer.handle(_up(Vector2(50, 140)), Vector2(50, 140))
	assert_false(pointer.hold.is_open(), "a drag opened the menu")
	assert_false(sheet.scrolls.is_empty(), "a drag did not scroll the sheet")

# ------------------------------------------------------- the league sheet ---

func _open_hub() -> LeagueScreen:
	season = LeagueSeason.create("Long Press", "generated", "fixture_days", SEED)
	assert_not_null(season, "the season was not created")
	var screen := LeagueScreen.new()
	add_child(screen)
	screen.ui_scale = 1.0
	screen.touch = true
	screen.size = Vector2(1280, 800)
	screen.open_season(season)
	return screen

## The first club name the hub painted, in design space (the sheet is not scrolled
## when it opens, so the strip is already where the pointer can reach it).
func _first_name(screen: LeagueScreen) -> Dictionary:
	for zone in screen.rows_names.zones:
		return zone
	return {}

func test_the_hub_opens_the_menu_from_a_fixture_name() -> void:
	var screen := _open_hub()
	await get_tree().process_frame
	var zone := _first_name(screen)
	assert_false(zone.is_empty(), "the hub painted no club name")
	var club := str(zone["club_id"])
	var at: Vector2 = (zone["rect"] as Rect2).get_center()
	var pointer := SheetPointer.new(screen)
	pointer.hold = screen.interest
	pointer.handle(_down(at), at)
	screen._process(InterestPress.HOLD + 0.01)
	assert_true(screen.interest.is_open(), "the hub did not raise the menu")
	assert_eq(screen.interest.menu.club_id, club, "the menu named the wrong club")
	pointer.handle(_up(at), at)
	assert_true(screen.interest.is_open(), "the hub's opening release closed the menu")
	screen.close()
	screen.queue_free()

func test_the_hub_menu_door_writes_the_season() -> void:
	var screen := _open_hub()
	await get_tree().process_frame
	var zone := _first_name(screen)
	assert_false(zone.is_empty(), "the hub painted no club name")
	var club := str(zone["club_id"])
	var at: Vector2 = (zone["rect"] as Rect2).get_center()
	screen.interest.press_at(at)
	screen.interest.tick(InterestPress.HOLD + 0.01)
	var vp := screen.design_vp()
	screen.click(screen.interest.menu.hit(screen.interest.menu.door_rect(vp).get_center(), vp))
	assert_true(season.record.interest.is_interested(club), "the door did not follow the club")
	assert_false(screen.interest.is_open(), "the menu stayed up after the write")
	assert_false(screen.rows_names.zones.is_empty(), "the sheet did not repaint after the write")
	screen.close()
	screen.queue_free()

func test_escape_puts_the_menu_away_before_the_sheet() -> void:
	var screen := _open_hub()
	await get_tree().process_frame
	var zone := _first_name(screen)
	var at: Vector2 = (zone["rect"] as Rect2).get_center()
	screen.interest.press_at(at)
	screen.interest.tick(InterestPress.HOLD + 0.01)
	assert_true(screen.key(KEY_ESCAPE), "the key was not taken")
	assert_false(screen.interest.is_open(), "ESC left the menu up")
	assert_true(screen.is_open(), "ESC closed the season sheet as well")
	screen.close()
	screen.queue_free()

# ------------------------------------------------------- the fixture picker ---

func test_the_picker_holds_a_club_card() -> void:
	season = LeagueSeason.create("Picker Press", "generated", "fixture_days", SEED)
	assert_not_null(season, "the season was not created")
	var picker = load("res://scripts/ui/team_select.gd").new()
	add_child(picker)
	picker.ui_scale = 1.0
	picker.size = Vector2(1280, 800)
	picker.setup("MUN", "MCI")
	await get_tree().process_frame
	var card := Rect2()
	for b in picker.buttons:
		if str(b["id"]) == "team_home":
			card = b["rect"]
	assert_gt(card.size.x, 0.0, "the picker painted no home card")
	var at := card.get_center()
	assert_true(picker.interest.press_at(at), "a club card was not watched")
	picker.interest.tick(InterestPress.HOLD + 0.01)
	assert_true(picker.interest.is_open(), "the picker did not raise the menu")
	assert_eq(picker.interest.menu.club_id, "MUN", "the picker named the wrong club")
	var vp: Vector2 = picker.design_vp()
	picker.click(picker.button_at(picker.interest.menu.door_rect(vp).get_center()))
	assert_true(season.record.interest.is_interested("MUN"), "the picker's door did not follow the club")
	picker.queue_free()

# ---------------------------------------------------------------- the HUD ---

func _match() -> Node2D:
	var game := Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game._on_fixture_confirmed("MUN", "MCI")
	TestBriefing.kick(game)
	game.paused = true
	game.hud.queue_redraw()
	await get_tree().process_frame
	return game

func _hud_door(game: Node2D, id: String) -> Rect2:
	for b in game.hud.buttons:
		if str(b["id"]) == id:
			return b["rect"]
	return Rect2()

func _press_at(game: Node2D, r: Rect2, pressed: bool) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = pressed
	ev.position = r.get_center() * game.hud_scale
	game._input(ev)

func test_the_hud_holds_a_club_name() -> void:
	season = LeagueSeason.create("Hud Press", "generated", "fixture_days", SEED)
	var game := await _match()
	var door := _hud_door(game, "team_0")
	assert_gt(door.size.x, 0.0, "the overlay painted no home club door")
	_press_at(game, door, true)
	var at: Vector2 = door.get_center()
	assert_true(game.hud.interest.is_open() or game.hud.interest.press.watching,
		"the overlay did not watch the club name it was pressed on")
	game.hud.interest.tick(InterestPress.HOLD + 0.01)
	assert_true(game.hud.interest.is_open(), "the overlay did not raise the menu")
	assert_eq(game.hud.interest.menu.club_id, "MUN", "the overlay named the wrong club")
	_press_at(game, door, false)
	assert_true(game.hud.interest.is_open(), "the opening release closed the menu")
	var vp: Vector2 = game.hud.design_vp()
	assert_eq(game.hud.button_at(game.hud.interest.menu.door_rect(vp).get_center()),
		InterestMenu.TOGGLE, "the overlay did not hand the press to the menu")
	game.hud.interest.click(InterestMenu.TOGGLE)
	assert_true(season.record.interest.is_interested("MUN"), "the overlay's door did not follow the club")
	# The overlay paints the gold from a set it reads when the season moves, not
	# from the save on every frame: the write must reach it.
	assert_true(bool(game.hud.followed.get("MUN", false)),
		"the overlay did not pick up the club it just followed")
	game.queue_free()

func test_the_overlay_follows_a_season_opening_and_closing() -> void:
	var game := await _match()
	assert_true(game.hud.followed.is_empty(), "no season, yet the overlay held a shortlist")
	season = LeagueSeason.create("Overlay Bind", "generated", "fixture_days", SEED)
	season.set_interest("MUN", true)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(bool(game.hud.followed.get("MUN", false)),
		"the overlay missed the season that opened under it")
	season.close()
	LeagueSeason.active = null
	await get_tree().process_frame
	await get_tree().process_frame
	assert_true(game.hud.followed.is_empty(),
		"the overlay kept a shortlist after its season closed")
	game.queue_free()

func test_a_short_tap_on_a_club_name_still_opens_its_page() -> void:
	var game := await _match()
	var door := _hud_door(game, "team_0")
	_press_at(game, door, true)
	_press_at(game, door, false)
	assert_false(game.hud.interest.is_open(), "a short tap opened the menu")
	assert_true(game.wiki_host.is_open(), "a short tap on the club lost its page")
	game.wiki_host.close()
	game.queue_free()

# ------------------------------------------------------- the encyclopedia ---

func _wiki() -> Control:
	var screen: Control = Control.new()
	screen.set_script(load("res://scripts/ui/wiki_screen.gd"))
	add_child(screen)
	screen.ui_scale = 1.0
	screen.size = Vector2(1280, 800)
	return screen

func test_the_league_page_names_each_club_row() -> void:
	season = LeagueSeason.create("Wiki Press", "generated", "fixture_days", SEED)
	var screen := _wiki()
	screen.open(WikiModel.LEAGUE, "")
	await get_tree().process_frame
	var zone := {}
	for z in screen.body.names.zones:
		zone = z
		break
	assert_false(zone.is_empty(), "the league page painted no club name")
	var at: Vector2 = (zone["rect"] as Rect2).get_center() + screen.body.position
	assert_eq(screen.body.club_at(at), str(zone["club_id"]), "the page named the wrong club")
	assert_true(screen.interest.press_at(at), "the page did not watch the club name")
	assert_true(screen.interest.tick(InterestPress.HOLD + 0.01), "the page never raised the menu")
	assert_eq(screen.interest.menu.club_id, str(zone["club_id"]), "the page's menu named another club")
	screen.queue_free()

func test_the_team_page_title_is_a_name_and_follows_gold() -> void:
	season = LeagueSeason.create("Wiki Team", "generated", "fixture_days", SEED)
	var screen := _wiki()
	screen.open(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	var zones: Array = screen.names.zones
	assert_false(zones.is_empty(), "the team page's title was not a name")
	assert_eq(str(zones[0]["club_id"]), "MUN", "the title named the wrong club")
	season.set_interest("MUN", true)
	screen.open(WikiModel.TEAM, "MUN")
	await get_tree().process_frame
	assert_true(bool(screen.body.followed.get("MUN", false)), "the followed club was not gold on the page")
	screen.queue_free()
