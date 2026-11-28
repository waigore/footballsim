extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_windows_443")
var CACHE_DIR := TestScratch.dir("cache_windows_443")
const SEED := 4331

var open_seasons: Array = []


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	for season in open_seasons:
		(season as LeagueSeason).close()
	open_seasons.clear()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _season(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"])
	assert_not_null(season, "%s was not created" % name)
	open_seasons.append(season)
	return season


func test_the_four_associations_ship_with_their_codes() -> void:
	var codes := MarketWindows.codes()
	assert_eq(codes.size(), 4, "the market does not ship four associations")
	for pair in [["ENG", "FA"], ["ESP", "RFEF"], ["GER", "DFB"], ["ITA", "FIGC"]]:
		assert_true(codes.has(str(pair[0])), "%s is not an association" % str(pair[0]))
		assert_eq(MarketWindows.code(str(pair[0])), str(pair[1]), "%s has the wrong code" % str(pair[0]))


func test_the_state_comes_from_the_date_alone() -> void:
	var summer := MarketWindows.state("2026-08-01", "ENG")
	assert_true(bool(summer.get("open", false)), "August is not in the English window")
	assert_eq(str(summer.get("opens_on", "")), "2026-06-10", "the summer window opens on another day")
	assert_eq(str(summer.get("closes_on", "")), "2026-09-01", "the summer window closes on another day")
	assert_eq(str(summer.get("source", "")), "real", "the shipped season is not marked real")
	var shut := MarketWindows.state("2026-09-02", "ENG")
	assert_false(bool(shut.get("open", false)), "2 September is still in the window")
	assert_eq(str(shut.get("opens_on", "")), "2027-01-01", "the closed state loses the opening date")
	assert_eq(str(shut.get("season_label", "")), "2026-27", "the closed state loses its season")
	var winter := MarketWindows.state("2027-01-01", "ENG")
	assert_true(bool(winter.get("open", false)), "1 January is not in the English winter window")
	assert_eq(str(winter.get("id", "")), "winter", "the winter window has the wrong id")


func test_a_jump_across_the_window_still_ticks_each_day() -> void:
	var season := _season("Window Jump")
	assert_eq(MarketTick.window_days("2026-08-30", "2026-09-03", "ENG"), 2,
		"31 August and 1 September are not both in the window")
	var ticked := MarketTick.advance(season.save, "2026-08-30", "2026-09-03")
	assert_true(bool(ticked.get("ok", false)), "the jump did not tick")
	assert_eq(int(ticked.get("days", 0)), 4, "the jump did not walk every calendar date")
	assert_eq(str(ticked.get("date", "")), "2026-09-03", "the market day is not the clock's date")
	var again := MarketTick.advance(season.save, "2026-08-30", "2026-09-03")
	assert_true(bool(again.get("ok", false)), "the repeated jump was refused outright")
	assert_eq(int(again.get("days", 0)), 0, "re-opening the same date ticked it twice")


func test_a_reload_mid_date_does_no_second_tick() -> void:
	var season := _season("Reload Guard")
	MarketTick.advance(season.save, "2026-08-20", "2026-08-21")
	assert_eq(str(season.save.meta.get(MarketTick.DAY_KEY, "")), "2026-08-21",
		"the save does not remember the market day")
	season.save.reload()
	assert_eq(str(season.save.meta.get(MarketTick.DAY_KEY, "")), "2026-08-21",
		"the market day did not survive a reload")
	assert_false(bool(MarketTick.advance(season.save, "2026-08-21", "2026-08-21").get("ok", false)),
		"the same date ticked again")
	var walked := MarketTick.walk(season.save, "2026-08-20", "2026-08-21")
	assert_eq(walked, 0, "a reload re-walked a date it had already ticked")


func test_a_fee_deal_in_june_is_closed_but_a_free_agent_signs() -> void:
	var fee := MarketWindows.allows(MarketWindows.FEE, "2026-06-05", "ENG", "ENG")
	assert_false(bool(fee.get("ok", false)), "a fee deal signed before the window")
	assert_eq(str(fee.get("reason", "")), "window_closed", "the refusal has no reason")
	assert_eq(str(fee.get("opens_on", "")), "2026-06-10", "the refusal promises no opening")
	var free := MarketWindows.allows(MarketWindows.FREE_AGENT, "2026-06-05", "ENG", "ENG")
	assert_true(bool(free.get("ok", false)), "a free agent could not sign in June")
	assert_eq(str(free.get("reason", "")), "free_agent", "the free-agent exception is unnamed")
	var in_window := MarketWindows.allows(MarketWindows.FEE, "2026-08-01", "ENG", "ENG")
	assert_true(bool(in_window.get("ok", false)), "a fee deal inside the window was refused")
	assert_eq(str(in_window.get("window_id", "")), "2026-27-summer", "the deal carries no window id")


func test_the_buying_association_governs_a_cross_association_deal() -> void:
	var english_buyer := MarketWindows.allows(MarketWindows.FEE, "2027-01-01", "ENG", "ESP")
	assert_true(bool(english_buyer.get("ok", false)),
		"an English buyer was refused while England's window is open")
	var spanish_buyer := MarketWindows.allows(MarketWindows.FEE, "2027-01-01", "ESP", "ENG")
	assert_false(bool(spanish_buyer.get("ok", false)),
		"a Spanish buyer signed before Spain's winter window opened")
	assert_eq(str(spanish_buyer.get("opens_on", "")), "2027-01-02",
		"the Spanish refusal loses its opening date")


func test_a_later_season_is_generated_and_labelled() -> void:
	var generated := MarketWindows.windows("2027-28", "ENG")
	assert_eq(generated.size(), 2, "a generated season has no two windows")
	var summer: Dictionary = generated[0]
	var winter: Dictionary = generated[1]
	assert_eq(str(summer.get("source", "")), "generated", "a generated window is not labelled")
	assert_eq(str(summer.get("open", "")), "2027-06-10", "the generated summer opens elsewhere")
	assert_eq(str(winter.get("open", "")), "2028-01-01", "the generated winter opens elsewhere")
	var state := MarketWindows.state("2027-07-05", "ENG")
	assert_true(bool(state.get("open", false)), "a generated season's summer is closed")
	assert_eq(str(state.get("source", "")), "generated", "the state hides that its dates are generated")


func test_no_window_state_table_exists() -> void:
	var season := _season("No Table")
	assert_not_null(season, "the save was not created")
	for row in PLDatabase.rows("SELECT name FROM sqlite_master WHERE type = 'table';"):
		assert_false(str(row["name"]).contains("window"), "%s keeps window state" % str(row["name"]))


func test_stub_entrants_are_not_market_participants() -> void:
	var real := PLDatabase.row("SELECT * FROM club WHERE competition_id = 'PL' LIMIT 1;")
	assert_true(MarketWindows.is_participant(real), "a league club is not a market participant")
	assert_eq(MarketWindows.country_of_club(real), "ENG", "the league country did not map to FA")
	var stub := PLDatabase.row("SELECT * FROM club WHERE stub = 1 LIMIT 1;")
	assert_false(MarketWindows.is_participant(stub), "a cup stub is a market participant")


func test_the_market_roll_is_keyed_by_the_save_and_the_date() -> void:
	var season := _season("Market Roll")
	var first := MarketTick.roll(season.save, "2026-08-20", "deal")
	assert_almost_eq(MarketTick.roll(season.save, "2026-08-20", "deal"), first, 0.0000001,
		"the same date and key rolled differently")
	assert_ne(MarketTick.roll(season.save, "2026-08-21", "deal"), first, "another date rolled the same")
	assert_ne(MarketTick.roll(season.save, "2026-08-20", "news"), first, "another key rolled the same")
	assert_true(first >= 0.0 and first < 1.0, "the market roll is not a unit draw")


func test_association_names_and_club_countries_map() -> void:
	MarketWindows.reset()
	assert_eq(MarketWindows.name("ENG"), "England", "England lost its association name")
	assert_eq(MarketWindows.name("ESP"), "Spain", "Spain lost its association name")
	assert_eq(MarketWindows.country_of_club({"competition_id": "LL"}), "ESP",
		"La Liga does not map to Spain")
	assert_eq(MarketWindows.country_of_club({"competition_id": "BL"}), "GER",
		"the Bundesliga does not map to Germany")
	assert_eq(MarketWindows.country_of_club({"competition_id": "SA"}), "ITA",
		"Serie A does not map to Italy")
	assert_eq(MarketWindows.country_of_club({"competition_id": "XX", "country": "ESP"}), "ESP",
		"a known country field is ignored")
	assert_eq(MarketWindows.country_of_club({"competition_id": "XX", "country": "ZZ"}), "",
		"an unknown country still maps")
	assert_false(MarketWindows.is_participant({}), "an empty club is a participant")


func test_edge_dates_and_tick_guards() -> void:
	assert_eq(MarketWindows.season_label("2026"), "", "a short date still labels a season")
	assert_eq(MarketWindows.windows("", "ENG").size(), 0, "a blank label still yields windows")
	assert_eq(MarketWindows.windows("2026-27", "ZZ").size(), 0, "an unknown country still yields windows")
	var shut := MarketWindows.state("", "ENG")
	assert_false(bool(shut.get("open", false)), "a blank date opens a window")
	assert_eq(MarketWindows.board("2026-08-01").size(), 4, "the board does not list every association")
	assert_false(bool(MarketTick.advance(null, "2026-08-01", "2026-08-02").get("ok", false)), "a null season still ticks")
	assert_eq(MarketTick.walk(null, "2026-08-01", "2026-08-02"), 0, "a null walk still advances")
	assert_eq(MarketTick.window_days("", "2026-08-02", "ENG"), 0, "a blank from-date still counts")
	assert_true(MarketTick.roll(null, "2026-08-20", "deal") >= 0.0, "a null season cannot roll")
