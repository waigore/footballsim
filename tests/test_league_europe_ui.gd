extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_test_league_europe_ui")
var CACHE_DIR := TestScratch.dir("cache_test_league_europe_ui")
const SEED := 6161
const WIDE := Vector2(1600, 900)
const PHONE := Vector2(913, 411)

var season: LeagueSeason = null
var screen: LeagueScreen = null


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	season = LeagueSeason.create("Europe UI", "generated", "fixture_days", SEED,
		["PL"], false, true)
	screen = LeagueScreen.new()
	add_child(screen)
	screen.size = WIDE
	screen.ui_scale = 1.0


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


func _open(vp: Vector2 = WIDE, touch: bool = false) -> void:
	screen.season = season
	screen.touch = touch
	screen.size = vp
	screen.nav.clear()
	screen.mode = LeagueScreen.MODE_HUB
	screen.visible = true
	screen.refresh()


func _ids() -> Array:
	var out: Array = []
	for item in screen.buttons:
		out.append(str(item["id"]))
	return out


func test_the_panel_carries_a_europe_row_with_its_own_icon() -> void:
	var found := {}
	for row in LeaguePanel.ITEMS:
		found[str((row as Dictionary)["id"])] = row
	assert_true(found.has("nav:europe"), "the panel has no Europe row")
	var row: Dictionary = found["nav:europe"]
	assert_eq(str(row["icon"]), "europe", "the Europe row has no icon of its own")
	assert_eq(str(row["pose"]), "europe", "the Europe row names no pose")
	assert_true(ResourceLoader.exists("res://assets/ui/league/europe.png"),
		"the Europe icon asset is missing")


func test_the_panel_door_opens_the_hub_and_lists_the_three_cards() -> void:
	_open()
	LeaguePanelDoors.nav(screen, "europe")
	assert_eq(screen.mode, LeagueScreen.MODE_EUROPE, "the Europe row did not open the hub")
	assert_true(_ids().has("europe:UCL"), "the hub has no Champions League card")
	assert_true(_ids().has("europe:UEL"), "the hub has no Europa League card")
	assert_true(_ids().has("europe:UECL"), "the hub has no Conference League card")
	assert_true(_ids().has("continue"), "the hub has no Continue door")


func test_a_card_opens_its_competition_with_the_round_rail() -> void:
	_open()
	LeagueEuropeActions.open(screen)
	screen.click("europe:UCL")
	assert_eq(screen.mode, LeagueScreen.MODE_EUROPE_STAGE, "the card did not open its stage")
	assert_eq(str(screen.europe_comp), "UCL", "the stage opened another competition")
	var ids := _ids()
	assert_true(ids.has("europeround:Q1"), "the rail has no first qualifying round")
	assert_true(ids.has("europehub"), "the stage has no Europe door")
	assert_true(ids.has("back"), "the stage has no BACK")


func test_the_rail_moves_the_stage_between_rounds() -> void:
	_open()
	LeagueEuropeActions.open(screen)
	LeagueEuropeActions.stage(screen, "UCL")
	screen.click("europeround:Q1")
	assert_eq(str(screen.europe_round), "Q1", "the rail did not pick the first round")
	var has_tie := false
	for item in screen.buttons:
		if str(item["id"]).begins_with("match:"):
			has_tie = true
	assert_false(has_tie, "an unplayed qualifying round offers a report")
	screen.click("europeround:LP")
	assert_eq(str(screen.europe_round), LeagueUefa.LEAGUE_STAGE, "the rail did not reach the phase")


func test_the_league_phase_paints_rows_and_scrolls_on_a_phone() -> void:
	var guard := 0
	while guard < 200 and not LeagueUefa.has_stage("UCL", LeagueUefa.LEAGUE_STAGE):
		season.advance()
		guard += 1
	for vp in [WIDE, PHONE]:
		_open(vp, vp == PHONE)
		LeagueEuropeActions.stage(screen, "UCL")
		screen.click("europeround:LP")
		var clubs := 0
		for item in screen.buttons:
			if str(item["id"]).begins_with("club:"):
				clubs += 1
		assert_eq(clubs, 36, "the phase painted %d clubs at %s" % [clubs, vp])
		assert_true(screen.body.content_height > screen.body.size.y - 200.0,
			"the phase body has no height at %s" % vp)


func test_a_played_tie_offers_its_report() -> void:
	var first := LeagueUefa.first_round("UCL")
	var guard := 0
	while guard < 60 and not LeagueUefa.has_stage("UCL", LeagueUefa.after("UCL", first)):
		season.advance()
		guard += 1
	_open()
	LeagueEuropeActions.stage(screen, "UCL")
	screen.click("europeround:" + first)
	var reports := 0
	for item in screen.buttons:
		if str(item["id"]).begins_with("match:"):
			reports += 1
	assert_gte(reports, 1, "no played tie offers its report")


func test_back_walks_the_stage_to_the_hub_and_stops_there() -> void:
	_open()
	LeagueEuropeActions.open(screen)
	LeagueEuropeActions.stage(screen, "UCL")
	screen.click("back")
	assert_eq(screen.mode, LeagueScreen.MODE_EUROPE, "BACK left the stage for nowhere")
	screen.click("back")
	assert_true(screen.visible, "BACK at the hub root closed the season")
	assert_eq(screen.mode, LeagueScreen.MODE_HUB, "BACK at the hub root did not return to the page it came from")


func test_a_domestic_save_reads_an_honest_hub() -> void:
	var domestic := LeagueSeason.create("No Europe", "generated", "fixture_days", SEED + 3,
		["PL"], false, false)
	screen.season = domestic
	screen.mode = LeagueScreen.MODE_EUROPE
	screen.size = PHONE
	screen.touch = true
	screen.visible = true
	screen.refresh()
	assert_false(_ids().has("europe:UCL"), "a domestic save lists a Champions League card")
	var view: Dictionary = LeagueView.build(screen)
	assert_false(bool(view["on"]), "a domestic save's hub claims Europe is on")
	domestic.close()
	season = LeagueSeason.create("Europe UI", "generated", "fixture_days", SEED,
		["PL"], false, true)


func test_the_wizard_toggle_rides_the_save() -> void:
	_open()
	screen.mode = LeagueScreen.MODE_WIZARD
	screen.wizard = {"name": "Toggle", "calendar_mode": "generated",
		"advance_mode": "fixture_days", "competitions": ["PL"], "uefa": false, "error": ""}
	screen.refresh()
	assert_true(_ids().has("uefa"), "the wizard has no UEFA toggle")
	screen.click("uefa")
	assert_true(bool(screen.wizard["uefa"]), "the toggle did not switch Europe on")
	screen.click("uefa")
	assert_false(bool(screen.wizard["uefa"]), "the toggle did not switch Europe back off")
	screen.click("create")
	assert_not_null(screen.season, "the wizard created no season")
	assert_eq(str(screen.season.save.meta.get("uefa", "")), "off",
		"a save created with the toggle off still runs Europe")
	screen.season.close()
	screen.season = null
	screen.mode = LeagueScreen.MODE_WIZARD
	screen.wizard = {"name": "Europe Save", "calendar_mode": "generated",
		"advance_mode": "fixture_days", "competitions": ["PL"], "uefa": true, "error": ""}
	screen.refresh()
	screen.click("create")
	assert_not_null(screen.season, "the wizard created no European season")
	assert_eq(str(screen.season.save.meta.get("uefa", "")), "on",
		"a save created with the toggle on does not run Europe")
	assert_eq(LeagueEurope.active(screen.season.save).size(), 3,
		"the European save does not carry three competitions")
	screen.season.close()
	screen.season = season
	LeagueSeason.active = season
	screen.mode = LeagueScreen.MODE_HUB
	screen.refresh()
