extends GdToolsTest

## The interest context menu and its team-name surfaces: the league sheets,
## the encyclopedia, the fixture picker and the match HUD. One menu, one
## shortlist write, and no menu at all when no league save is open. Plus the
## Save As rules the System dialog leans on.

var SAVE_DIR := TestScratch.dir("saves_test_surfaces_103")
var CACHE_DIR := TestScratch.dir("cache_test_surfaces_103")
var PREFS := TestScratch.file("test_surfaces_103.cfg")

var game = null
var season: LeagueSeason = null

func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	LeagueInterest.current = null
	game = Node2D.new()
	game.set_script(load("res://scripts/main.gd"))
	add_child(game)
	game.menus.shell.prefs_path = PREFS
	await get_tree().process_frame
	game._on_fixture_confirmed("MUN", "MCI")
	game.paused = true

func after_all() -> void:
	if game != null:
		game.queue_free()
		await get_tree().process_frame
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	LeagueInterest.current = null
	LeagueSave.close()
	season = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()

func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

## One generated season for the interest cases; the HUD/picker cases need a
## save to write to and nothing more.
func open_season() -> void:
	if season == null:
		season = LeagueSeason.create("Surfaces", "generated", "fixture_days", 515)
	assert_not_null(season, "the season was not created: %s" % LeagueSave.last_error)

func close_season() -> void:
	if LeagueSeason.active != null:
		LeagueSeason.active.close()
	season = null
	LeagueInterest.current = null
	if game.interest != null:
		game.interest.hide()

# ------------------------------------------------------------------- menu ---

func test_the_menu_needs_a_club_and_clamps_inside_the_window() -> void:
	var menu := InterestMenu.new()
	menu.show_at("", "Nobody", Vector2(10.0, 10.0))
	assert_false(menu.open, "an empty club opened the menu")
	menu.show_at("MUN", "Man Utd", Vector2(4000.0, 3000.0))
	assert_true(menu.open, "the menu did not open")
	var vp := Vector2(800.0, 600.0)
	var r := menu.rect(vp)
	assert_lte(r.end.x, vp.x, "the menu ran past the right edge")
	assert_lte(r.end.y, vp.y, "the menu ran past the bottom edge")
	assert_true(menu.action_rect(vp).has_point((menu.action_rect(vp) as Rect2).get_center()),
		"the action row is not inside the menu")
	assert_eq(menu.hit(r.get_center(), vp), "interest:toggle", "the action row did not hit")
	assert_eq(menu.hit(Vector2(1.0, 1.0), vp), "interest:close", "an outside press is not a dismissal")
	menu.hide()
	assert_false(menu.open, "hide left the menu open")
	assert_eq(menu.hit(r.get_center(), vp), "", "a closed menu still hit-tests")

func test_narrow_windows_still_hold_the_menu() -> void:
	var menu := InterestMenu.new()
	menu.show_at("MUN", "Man Utd", Vector2(400.0, 300.0))
	var vp := Vector2(120.0, 90.0)
	var r := menu.rect(vp)
	assert_lte(r.end.x, vp.x, "the menu escaped a phone-width window")
	assert_lte(r.end.y, vp.y, "the menu ran off a phone-height window")
	assert_gte(r.size.x, 60.0, "the menu collapsed below use")
	assert_eq(menu.hit(menu.action_rect(vp).get_center(), vp), "interest:toggle", "a phone press missed the action")

func test_applying_the_menu_writes_the_open_save_only() -> void:
	open_season()
	var menu := InterestMenu.new()
	menu.show_at("MUN", "Man Utd", Vector2(200.0, 200.0))
	menu.apply()
	assert_true(LeagueSeason.active.interest.has("MUN"), "the menu did not mark the club")
	assert_true(LeagueSeason.active.dirty, "marking left the season clean")
	assert_false(menu.open, "the menu stayed after applying")
	game.interest.show_at("MUN", "Man Utd", Vector2(200.0, 200.0))
	game.interest.apply()
	assert_false(LeagueSeason.active.interest.has("MUN"), "a second apply did not remove the club")
	# With no season there is nothing to write and nothing to crash.
	var orphan := InterestMenu.new()
	close_season()
	orphan.show_at("MUN", "Man Utd", Vector2(200.0, 200.0))
	orphan.apply()
	assert_false(orphan.open, "an orphan menu stayed open")
	assert_null(LeagueSeason.active, "the season came back from nowhere")

# ------------------------------------------------------- hud / picker club ---

func test_the_hud_labels_name_their_clubs() -> void:
	open_season()
	assert_eq(game.engine.teams[0]["id"], "MUN", "the fixture did not start as arranged")
	game.mouse = _hud_point("team_0")
	assert_eq(InterestEntry.hud_club(game), "MUN", "the home label did not read as MUN")
	game.mouse = _hud_point("team_1")
	assert_eq(InterestEntry.hud_club(game), "MCI", "the away label did not read as MCI")
	game.mouse = Vector2(2.0, 2.0)
	assert_eq(InterestEntry.hud_club(game), "", "a press on empty chrome named a club")

## The design-space centre of one of the HUD's own hit rectangles.
func _hud_point(id: String) -> Vector2:
	for b in game.hud.buttons:
		if str(b["id"]) == id:
			return ((b["rect"] as Rect2).get_center()) * game.hud_scale
	return Vector2.ZERO

func test_show_opens_the_menu_over_the_club() -> void:
	open_season()
	game.mouse = _hud_point("team_0")
	assert_true(InterestEntry.show(game, "MUN"), "the HUD long-press opened nothing")
	assert_true(game.interest.open, "the shared menu stayed shut")
	assert_eq(game.interest.club_id, "MUN", "the menu is about the wrong club")
	assert_eq(game.interest.club_name, "Manchester United", "the menu did not name the club")
	game.interest.apply()
	assert_true(LeagueSeason.active.interest.has("MUN"), "the HUD menu did not mark the club")

func test_without_a_season_the_hud_is_inert() -> void:
	close_season()
	game.mouse = _hud_point("team_0")
	assert_eq(InterestEntry.hud_club(game), "", "no save still named a club")
	assert_false(InterestEntry.show(game, "MUN"), "no save still opened the menu")
	assert_false(game.interest.open, "the menu opened with no save")

func test_the_picker_cards_name_their_clubs() -> void:
	open_season()
	game.open_select()
	assert_true(game.select_open, "the fixture sheet did not open")
	await get_tree().process_frame
	game.selector.mouse = _picker_point("team_home")
	assert_eq(InterestEntry.picker_club(game.selector), str(game.selector.home_id()),
		"the home card did not name the home club")
	game.selector.mouse = _picker_point("team_away")
	assert_eq(InterestEntry.picker_club(game.selector), str(game.selector.away_id()),
		"the away card did not name the away club")
	game.selector.mouse = Vector2(1.0, 1.0)
	assert_eq(InterestEntry.picker_club(game.selector), "", "empty picker chrome named a club")
	assert_false(InterestEntry.show(game, InterestEntry.picker_club(game.selector)),
		"a press off the cards opened the menu")
	game._close_select()

func _picker_point(id: String) -> Vector2:
	for b in game.selector.buttons:
		if str(b["id"]) == id:
			return (b["rect"] as Rect2).get_center()
	return Vector2.ZERO

func _tap(at: Vector2, hold: bool = false) -> void:
	game.input.hold_ms = 0 if hold else 10000
	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = at
	game._input(down)
	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = at
	game._input(up)
	game.input.hold_ms = InterestMenu.HOLD_MS

func test_a_long_press_on_the_hud_label_marks_the_club() -> void:
	open_season()
	game.interest.hide()
	_tap(_hud_point("team_0"), true)
	assert_true(game.interest.open, "the HUD hold raised no menu")
	assert_eq(game.interest.club_id, str(game.engine.teams[0]["id"]), "the hold found the wrong club")
	var action: Rect2 = game.interest.action_rect(game.view.design(game.get_viewport().get_visible_rect().size))
	_tap(action.get_center())
	assert_true(LeagueSeason.active.interest.has(str(game.engine.teams[0]["id"])),
		"the HUD menu did not mark the club")
	assert_false(game.interest.open, "the HUD menu stayed open")

func test_a_short_tap_on_the_hud_label_still_opens_the_club_page() -> void:
	open_season()
	game.interest.hide()
	_tap(_hud_point("team_0"))
	assert_false(game.interest.open, "a short tap raised the interest menu")
	assert_true(game.wiki_host.screen.is_open(), "a short tap no longer opens the club page")
	game.wiki_host.close()

func test_a_long_press_on_a_picker_card_marks_the_club() -> void:
	open_season()
	game.open_select()
	await get_tree().process_frame
	game.interest.hide()
	var at: Vector2 = _picker_point("team_home") * game.hud_scale
	_tap(at, true)
	assert_true(game.interest.open, "the picker hold raised no menu")
	assert_eq(game.interest.club_id, str(game.selector.home_id()), "the picker hold found the wrong club")
	game.interest.apply()
	assert_true(LeagueSeason.active.interest.has(str(game.selector.home_id())),
		"the picker menu did not mark the club")
	game._close_select()

# --------------------------------------------------------------- the wiki ---

func test_the_encyclopedia_marks_a_club_from_its_page() -> void:
	open_season()
	game.wiki_host.open_page("team", "ARS")
	var screen = game.wiki_host.screen
	assert_eq(str(screen.current()["id"]), "ARS", "the club page did not open")
	var title_point := Vector2(120.0, 8.0)
	assert_eq(WikiInterest.team_at(screen, title_point), "ARS", "the page title is not a team name")
	assert_true(WikiInterest.open(screen, title_point), "the wiki did not raise the menu")
	assert_eq(str(screen.menu.club_id), "ARS", "the wiki menu is about the wrong club")
	WikiInterest.toggle(screen)
	assert_true(LeagueSeason.active.interest.has("ARS"), "the wiki toggle did not mark the club")
	assert_false(screen.menu.open, "the wiki menu stayed open")
	screen.menu.show_at("ARS", "Arsenal", title_point)
	WikiInterest.toggle(screen)
	assert_false(LeagueSeason.active.interest.has("ARS"), "a second toggle did not unmark")
	game.wiki_host.close()

func test_the_wiki_routes_its_menu_clicks() -> void:
	open_season()
	game.wiki_host.open_page("team", "ARS")
	var screen = game.wiki_host.screen
	screen.menu.show_at("ARS", "Arsenal", Vector2(160.0, 120.0))
	var vp: Vector2 = screen.design_vp()
	assert_eq(screen.button_at(screen.menu.action_rect(vp).get_center()), "interest:toggle",
		"the wiki menu action did not hit-test")
	screen.click("interest:toggle")
	assert_true(LeagueSeason.active.interest.has("ARS"), "the wiki click did not mark the club")
	assert_false(screen.menu.open, "the wiki click left the menu open")
	screen.menu.show_at("ARS", "Arsenal", Vector2(160.0, 120.0))
	screen.click("interest:close")
	assert_false(screen.menu.open, "the wiki close button left the menu open")
	game.wiki_host.close()

func test_the_wiki_ignores_non_team_pages_and_presses() -> void:
	open_season()
	game.wiki_host.open_page("league", "")
	var screen = game.wiki_host.screen
	assert_eq(WikiInterest.team_at(screen, Vector2(120.0, 8.0)), "", "the league title named a team")
	assert_false(WikiInterest.open(screen, Vector2(-40.0, -40.0)), "an empty press opened the menu")
	# A toggle with no club in the menu just closes it.
	screen.menu.show_at("", "", Vector2.ZERO)
	WikiInterest.toggle(screen)
	assert_false(screen.menu.open, "an empty menu survived the toggle")
	game.wiki_host.close()

func test_the_wiki_menu_is_inert_without_a_save() -> void:
	close_season()
	game.wiki_host.open_page("team", "ARS")
	var screen = game.wiki_host.screen
	assert_eq(WikiInterest.team_at(screen, Vector2(120.0, 8.0)), "", "no save still named a team")
	assert_false(WikiInterest.open(screen, Vector2(120.0, 8.0)), "no save still opened the menu")
	screen.menu.show_at("ARS", "Arsenal", Vector2(100.0, 100.0))
	WikiInterest.toggle(screen)
	assert_false(screen.menu.open, "no save left the menu open")
	assert_null(LeagueSeason.active, "no save made a season")
	game.wiki_host.close()

# ---------------------------------------------------------------- save as ---

func test_save_as_writes_a_named_copy_and_keeps_the_session() -> void:
	close_season()
	var save: LeagueSave = LeagueSave.create("Original", LeagueRules.defaults())
	assert_not_null(save, "the save was not created: %s" % LeagueSave.last_error)
	var slug := save.write_copy("Away Day")
	assert_eq(slug, "away-day", "Save As returned the wrong slug")
	assert_true(FileAccess.file_exists(SAVE_DIR.path_join("away-day.sqlite")), "Save As wrote no file")
	assert_eq(save.slug, "original", "Save As moved the session to the copy")
	var copy := LeagueSave.open(slug)
	assert_not_null(copy, "the copy did not reopen")
	assert_eq(copy.name(), "Away Day", "the copy kept the old name")
	assert_true(str(copy.meta.get("saved_at", "")) != "", "the copy has no save stamp")
	LeagueSave.close()

func test_quick_save_stamps_in_place_and_replaces_a_taken_name() -> void:
	close_season()
	var save: LeagueSave = LeagueSave.create("In Place", LeagueRules.defaults())
	assert_eq(save.write_copy("In Place"), "in-place", "the same name did not quick-save")
	assert_eq(save.slug, "in-place", "quick save changed the slug")
	assert_true(save.touch(), "Quick Save did not stamp the file")
	assert_true(str(save.meta.get("saved_at", "")) != "", "Quick Save left no stamp")
	# An explicit name that is already taken is overwritten, not suffixed.
	assert_eq(save.write_copy("In Place Again"), "in-place-again", "the first copy failed")
	save.put_meta("witness", "one")
	assert_eq(save.write_copy("In Place Again"), "in-place-again", "the second copy failed")
	var again := LeagueSave.open("in-place-again")
	assert_eq(str(again.meta.get("witness", "")), "one", "the overwrite did not carry the season")
	LeagueSave.close()

func test_save_as_names_edge_cases() -> void:
	close_season()
	var save: LeagueSave = LeagueSave.create("Edge", LeagueRules.defaults())
	assert_eq(save.write_copy(""), "", "a blank name wrote a copy")
	assert_eq(save.write_copy("   "), "", "a spaces-only name wrote a copy")
	assert_eq(save.write_copy("!!!"), "edge", "a name with no letters was not stamped in place")
	assert_eq(LeagueSave.slugify("Café United"), "caf-united", "an accented name was slugified oddly")
	LeagueSave.close()
	var closed := LeagueSave.new()
	assert_eq(closed.write_copy("Nowhere"), "", "a closed save wrote a file")

# ------------------------------------------------------------------ panel ---

func test_panel_gaps_and_header_do_not_dismiss() -> void:
	var panel := LeaguePanel.new()
	panel.open()
	panel.settle()
	var vp := Vector2(800.0, 600.0)
	assert_eq(panel.hit(Vector2(20.0, 20.0), vp), "", "the panel header dismissed the panel")
	assert_eq(panel.hit(Vector2(vp.x - 10.0, vp.y * 0.5), vp), "panel:close", "a scrim press did not dismiss")
	assert_eq(panel.hit(panel.item_rect(vp, 4).get_center(), vp), "nav:stats", "a row did not hit")
	assert_eq(panel.hit(panel.tab_rect(vp).get_center(), vp), "", "the tab hit while the panel was open")
	panel.close()
	panel.settle()
	assert_eq(panel.hit(panel.tab_rect(vp).get_center(), vp), "panel", "a closed panel lost its tab")
	assert_false(panel.is_open(), "a closed panel still reads open")

func test_panel_slide_settles_and_never_blocks() -> void:
	var panel := LeaguePanel.new()
	assert_false(panel.update(0.016), "a settled panel spent an update")
	panel.toggle()
	assert_true(panel.update(0.016), "an opening panel reported nothing to paint")
	assert_false(panel.settled(), "the slide skipped straight to settled")
	panel.update(LeaguePanel.SLIDE)
	assert_true(panel.settled(), "the slide did not settle")
	assert_false(panel.update(0.016), "a settled panel kept painting")
	assert_almost_eq(LeaguePanel.eased(0.0), 0.0, 0.001, "the ease starts off zero")
	assert_almost_eq(LeaguePanel.eased(1.0), 1.0, 0.001, "the ease ends off one")
