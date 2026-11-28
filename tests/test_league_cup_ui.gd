extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_cup_ui_459")
var CACHE_DIR := TestScratch.dir("cache_test_cup_ui_459")
var PREFS := TestScratch.file("test_cup_ui_459.cfg")

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

func has_id(id: String) -> bool:
	for item in screen().buttons:
		if str(item["id"]) == id:
			return true
	return false

func open_wizard() -> void:
	game.menus.open_menu()
	for b in MenuScreen.door_rects(game.menus.shell.design_vp(), bool(game.menus.shell.has_match)):
		if str(b["id"]) == "new_league":
			press((b["rect"] as Rect2).get_center())
			return
	assert_true(false, "the menu lost its NEW LEAGUE door")

func create_season() -> void:
	open_wizard()
	press_id("create")
	assert_eq(screen().mode, "hub", "the wizard did not open a season")

func open_cups() -> void:
	screen().panel.open()
	screen().panel.settle()
	screen().refresh()
	assert_true(screen().panel.cups, "the open save carries no CUPS door")
	for i in range(LeaguePanel.rows(true).size()):
		if str(LeaguePanel.rows(true)[i]["id"]) == "nav:cups":
			press(screen().panel.item_rect(vp(), i).get_center())
			screen().panel.settle()
			assert_eq(screen().mode, "cups", "the drawer did not open the cups hub")
			return
	assert_true(false, "the drawer has no CUPS row")

func test_the_wizard_defaults_every_active_country_on() -> void:
	open_wizard()
	assert_eq(screen().mode, "wizard", "NEW LEAGUE did not open the form")
	assert_eq(screen().wizard.get("cups_off", []), [], "the wizard does not start with every cup on")
	assert_true(has_id("wcups:England"), "an England league is active with no DOMESTIC CUPS switch")
	assert_false(has_id("wcups:Spain"), "Spain has no active league but offers its cups")
	press_id("wcups:England")
	assert_eq(screen().wizard["cups_off"], ["England"], "the cups switch did not turn England off")
	press_id("wleague:LL")
	assert_true(has_id("wcups:Spain"), "La Liga did not bring its cups switch")
	assert_true(screen().wizard["competitions"].has("LL"), "the second league left the form")
	press_id("wleague:PL")
	assert_false(has_id("wcups:England"), "England lost its league but kept its cups switch")
	assert_true(has_id("wcups:Spain"), "Spain lost its cups switch with its league still on")

func test_the_italian_cups_switch_follows_serie_a() -> void:
	open_wizard()
	assert_false(has_id("wcups:Italy"), "Italy offered cups with no Italian league on")
	press_id("wleague:SA")
	assert_true(screen().wizard["competitions"].has("SA"), "Serie A left the form")
	assert_true(has_id("wcups:Italy"), "Serie A did not bring the Italian cups switch")
	press_id("wcups:Italy")
	assert_eq(screen().wizard["cups_off"], ["Italy"], "the Italian cups switch did not turn off")
	press_id("wleague:SA")
	assert_false(has_id("wcups:Italy"), "Serie A lost its league but kept its cups switch")

func test_a_country_switched_off_creates_a_save_without_its_cups() -> void:
	open_wizard()
	press_id("wleague:LL")
	press_id("wcups:England")
	assert_eq(LeagueWizardActions.cups_on(screen()), ["Spain"], "the wizard kept England's cups on")
	press_id("create")
	assert_eq(screen().mode, "hub", "the wizard did not open a season")
	assert_eq(LeagueCup.active_ids(LeagueSeason.active.save), ["CDR", "SCE"],
		"the save created with England's cups off still runs them")

func test_every_country_off_creates_a_save_that_runs_no_cups() -> void:
	open_wizard()
	press_id("wcups:England")
	press_id("create")
	assert_eq(screen().mode, "hub", "the wizard did not open a season")
	assert_eq(LeagueCup.active_ids(LeagueSeason.active.save), [],
		"a save created with its only cups switch off still runs cups")
	assert_false(LeagueScreenPages.has_cups(screen()), "the drawer still offers a CUPS door")
	assert_false(screen().panel.cups, "the drawer kept the CUPS row")

func test_a_cups_off_save_opens_with_cups_off() -> void:
	var plain := LeagueSeason.create("Cups Off", "generated", "fixture_days", 7788, ["PL"])
	assert_not_null(plain, "the cups-off season was not created")
	var slug := plain.save.slug
	plain.close()
	game.menus.league.open_save(slug)
	assert_eq(screen().mode, "hub", "the save did not open on its hub")
	assert_eq(LeagueCup.active_ids(LeagueSeason.active.save), [],
		"a save written before cups ran cups on reopen")
	assert_false(LeagueScreenPages.has_cups(screen()), "the reopened save offers a CUPS door")

func test_the_cups_hub_lists_each_cup_with_its_stage_and_night() -> void:
	create_season()
	assert_true(LeagueScreenPages.has_cups(screen()), "a cups save offers no CUPS door")
	open_cups()
	var rows: Array = screen().current_view().get("cups", [])
	assert_eq(rows.size(), 3, "the cups hub does not list England's three cups")
	var ids: Array = []
	for row in rows:
		var card: Dictionary = row
		ids.append(str(card["id"]))
		assert_true(str(card["id"]) in ["FAC", "EFLC", "CS"], "the hub lists an unknown cup")
		assert_true(str(card["stage_name"]) != "", "%s has no stage" % str(card["id"]))
		assert_true(str(card["next_date"]) != "", "%s has no cup night" % str(card["id"]))
		assert_gt(int(card["clubs"]), 1, "%s has no clubs still in it" % str(card["id"]))
		assert_true(has_id("cup:" + str(card["id"])), "the hub has no door into %s" % str(card["id"]))
	assert_eq(ids.size(), 3, "the hub lost a cup")
	assert_true(has_id("back"), "the cups hub lost BACK")
	assert_true(has_id("continue"), "the cups hub lost CONTINUE")

func test_a_cup_opens_its_rounds_and_bracket() -> void:
	create_season()
	open_cups()
	press_id("cup:FAC")
	assert_eq(screen().mode, "cup", "a cup card did not open its hub")
	var view: Dictionary = screen().current_view()
	assert_eq(str(view.get("id", "")), "FAC", "the cup hub opened another competition")
	assert_eq((view.get("rounds", []) as Array).size(), 8, "the FA Cup lost a round")
	assert_eq((view.get("ties", []) as Array).size(), 40, "the FA Cup first round is not forty ties")
	var first: Dictionary = (view["ties"] as Array)[0]
	assert_true(str(first.get("home_name", "")) != "" and str(first.get("away_name", "")) != "",
		"a bracket tie does not name both clubs")
	assert_true(has_id("cupbracket:FAC:R1"), "the cup hub has no BRACKET door")
	press_id("cupbracket:FAC:R1")
	assert_eq(screen().mode, "bracket", "the BRACKET door did not open the bracket")
	var rounds: Array = screen().current_view().get("rounds", [])
	assert_eq(rounds.size(), 8, "the bracket lost a round")
	for row in rounds:
		assert_true(str((row as Dictionary).get("name", "")) != "", "a bracket round has no name")
	var first_round: Dictionary = rounds[0]
	var ties: Array = first_round.get("ties", [])
	assert_eq(ties.size(), 40, "the bracket column lost its ties")
	var tie: Dictionary = ties[0]
	assert_true(str(tie.get("home_name", "")) != "" and str(tie.get("away_name", "")) != "",
		"a bracket tie does not name both clubs")

func test_a_played_cup_tie_opens_its_report() -> void:
	create_season()
	var fx := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'CS' AND stage = 'F' LIMIT 1;")
	assert_false(fx.is_empty(), "the Community Shield has no fixture")
	LeagueSeasonSim.fixture(LeagueSeason.active, fx)
	PLRepository.shared().invalidate()
	open_cups()
	press_id("cup:CS")
	var view: Dictionary = screen().current_view()
	var tie: Dictionary = (view["ties"] as Array)[0]
	assert_true(bool(tie.get("played", false)), "the settled Shield reads as unplayed")
	var door := str(tie.get("played_fixture", ""))
	assert_true(door != "", "a played tie kept no fixture id")
	assert_true(has_id("cupmatch:" + door), "a played tie has no report door")
	press_id("cupmatch:" + door)
	assert_eq(screen().mode, "report", "a played tie did not open its report")
	assert_false((screen().report as Dictionary).is_empty(), "the cup report has no fixture")

func test_the_draw_ceremony_reads_the_settled_draw_and_skips() -> void:
	create_season()
	open_cups()
	press_id("cup:EFLC")
	var stage := LeagueCupState.stage("EFLC")
	var before := LeagueCupView.fixtures_of("EFLC", stage)
	press_id("cupdraw:EFLC:" + stage)
	assert_eq(screen().mode, "cup_draw", "the DRAW door did not open the ceremony")
	var pairs: Array = screen().current_view().get("pairs", [])
	assert_eq(pairs.size(), before.size(), "the ceremony does not read every settled pair")
	assert_eq(int(screen().draw_state["shown"]), 0, "the ceremony opened fully revealed")
	LeagueCupDoors.tick(screen(), LeagueCupDrawSheet.REVEAL + 0.01)
	assert_eq(int(screen().draw_state["shown"]), 1, "the ceremony revealed no row on its clock")
	assert_true(has_id("skiptodraw"), "the ceremony has no SKIP door")
	press_id("skiptodraw")
	assert_eq(int(screen().draw_state["shown"]), pairs.size(), "SKIP did not settle the draw")
	press_id("back")
	assert_eq(screen().mode, "cup", "BACK left the cup for another page")
	var after := LeagueCupView.fixtures_of("EFLC", stage)
	assert_eq(str(after), str(before), "the ceremony redrew the settled draw")
	assert_false(LeagueCupView.pending_draw(LeagueSeason.active, "EFLC", stage),
		"a revealed draw still reads as pending")

func test_the_podium_reads_domestic_honours() -> void:
	var summary := {"competitions": [_section()],
		"cups": [{"id": "FAC", "name": "FA Cup", "short": "FA CUP",
		"winner_name": "Arsenal", "runner_up_name": "Chelsea", "home_goals": 2, "away_goals": 1,
		"pens_home": -1, "pens_away": -1, "extra_time": false}]}
	var lines := LeaguePodiumSheet.cups_lines(summary)
	assert_eq(lines.size(), 1, "the podium dropped a cup")
	var line: Dictionary = lines[0]
	assert_true(str(line["line"]).contains("Arsenal"), "the honours line does not name the winner")
	assert_true(str(line["line"]).contains("Chelsea"), "the honours line does not name the runner-up")
	assert_eq(str(line["score"]), "2 – 1", "the honours line does not carry the final's score")
	assert_gt(LeaguePodiumSheet.cups_height(summary), 0.0, "the honours block takes no height")
	var shootout := {"cups": [{"id": "EFLC", "name": "Carabao Cup", "short": "CARABAO CUP",
		"winner_name": "Leeds", "runner_up_name": "Hull", "home_goals": 1, "away_goals": 1,
		"pens_home": 4, "pens_away": 2, "extra_time": false}]}
	assert_true(str((LeaguePodiumSheet.cups_lines(shootout)[0] as Dictionary)["score"]).contains("PENS"),
		"a shootout final hides its penalties")
	var sheet := LeagueBook.new()
	var items: Array = sheet.podium_layout(vp(), {"summary": summary})
	var doors := 0
	for item in items:
		if str((item as Dictionary).get("id", "")) == "table":
			doors += 1
	assert_eq(doors, 1, "the podium lost its table door")

func test_a_cups_off_save_reads_no_honours() -> void:
	var season := LeagueSeason.create("No Cups Podium", "generated", "fixture_days", 3311)
	assert_not_null(season, "the season was not created")
	var summary := season.summary()
	assert_eq(LeaguePodiumSheet.cups_of(summary), [], "a cups-off season read domestic honours")
	assert_eq(LeaguePodiumSheet.cups_height(summary), 0.0, "the honours block took height anyway")
	season.close()

func _section() -> Dictionary:
	return {"id": "PL", "name": "Premier League", "short": "PL",
		"champion": {"club": "Arsenal", "club_id": "ENG-ARS1", "points": 88},
		"runner_up": {"club": "Chelsea", "club_id": "ENG-CHE1", "points": 84},
		"europe": [], "relegated": [], "rules": LeagueRules.defaults(), "table": []}


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)
	if FileAccess.file_exists(PREFS):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(PREFS))

func test_the_encyclopedia_reads_a_cup_bracket_and_honours() -> void:
	create_season()
	var page := WikiModel.page(WikiModel.CUP, "FAC")
	assert_eq(str(page["title"]), "FA CUP", "the cup page lost its name")
	assert_true(str(page["subtitle"]).contains("CLUBS IN"), "the cup subtitle reads no field")
	assert_true(_has_section(page, "BRACKET"), "the cup page has no bracket section")
	assert_true(_has_section(page, "FIXTURES AHEAD"), "the cup page has no fixtures ahead")
	assert_true(_has_note(page, "NO CUP TIE HAS BEEN PLAYED YET"),
		"an untouched cup claims a result")
	var facts := WikiCup.facts("FAC", "R1", {})
	assert_true(_fact(facts, "LEGS") == "ONE", "the FA Cup round reads two legs")
	assert_true(_fact(facts, "EXTRA TIME") == "YES", "the FA Cup round lost extra time")
	var carabao := WikiCup.facts("EFLC", "PR", {})
	assert_true(_fact(carabao, "EXTRA TIME") == "PENALTIES ONLY",
		"the Carabao preliminary round claims extra time")
	assert_eq(WikiCup.draw_note("EFLC", "PR"), "NORTH AND SOUTH POTS",
		"the regional draw note is wrong")
	assert_true(WikiCup.draw_note("FAC", "R1").contains("THE LOWER CLUB HOSTS"),
		"the lower-club host note is missing")
	assert_eq(WikiCup.draw_note("CS", "F"), "A NEUTRAL VENUE", "the Shield note is wrong")
	assert_eq(WikiCup.draw_note("FAC", "QF"), "AN OPEN DRAW FROM THE SEASON SEED",
		"the open draw note is wrong")
	assert_eq(WikiCup.subtitle("FAC", "", {}, true), "NOT DRAWN YET",
		"an undrawn cup reads a stage")
	var fx := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'FAC' AND stage = 'R1' LIMIT 1;")
	LeagueSeasonSim.fixture(LeagueSeason.active, fx)
	PLRepository.shared().invalidate()
	var played := WikiModel.page(WikiModel.CUP, "FAC")
	assert_true(_has_section(played, "LATEST RESULTS"), "the played cup lost its results")
	assert_false(_has_note(played, "NO CUP TIE HAS BEEN PLAYED YET"),
		"a played cup still says nothing was played")
	var shield := PLDatabase.row(
		"SELECT * FROM league_fixture WHERE competition_id = 'CS' AND stage = 'F' LIMIT 1;")
	LeagueSeasonSim.fixture(LeagueSeason.active, shield)
	PLRepository.shared().invalidate()
	var honour := WikiModel.page(WikiModel.CUP, "CS")
	assert_true(str(honour["subtitle"]).contains("WINNER"), "a settled cup has no winner line")
	assert_true(_fact(WikiCup.facts("CS", "F", LeagueCupState.honours("CS")), "RUNNER-UP") != "",
		"the cup facts lost the runner-up")

func _has_section(page: Dictionary, title: String) -> bool:
	for block in page.get("blocks", []):
		var row: Dictionary = block
		if str(row.get("k", "")) == "section" and str(row.get("text", "")) == title:
			return true
	return false

func _has_note(page: Dictionary, text: String) -> bool:
	for block in page.get("blocks", []):
		var row: Dictionary = block
		if str(row.get("k", "")) == "note" and str(row.get("text", "")) == text:
			return true
	return false

func _fact(facts: Array, key: String) -> String:
	for row in facts:
		var pair: Array = row
		if str(pair[0]) == key:
			return str(pair[1])
	return ""

