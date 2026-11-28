extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_finance_442")
var CACHE_DIR := TestScratch.dir("cache_market_finance_442")
const SEED := 6420

var opened: Array = []
var shared: LeagueSeason = null


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func after_all() -> void:
	for season in opened:
		(season as LeagueSeason).close()
	opened.clear()
	shared = null
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _fresh(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"], false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	return season


func _shared() -> LeagueSeason:
	if shared != null and LeagueSeason.active == shared:
		return shared
	shared = _fresh("Finance Read")
	return shared


func _club() -> String:
	return str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY name LIMIT 1;").get("id", ""))


func test_every_league_club_opens_solvent_and_inside_its_envelope() -> void:
	var season := _shared()
	var clubs := 0
	for row in PLDatabase.rows("SELECT * FROM club_finance ORDER BY club_id;"):
		var club_id := str(row["club_id"])
		clubs += 1
		assert_gte(int(row["cash"]), 0, "%s opens in debt" % club_id)
		assert_gte(int(row["revenue_base"]), 0, "%s has no revenue anchor" % club_id)
		assert_lte(MarketFinance.annual_wages(club_id), int(row["wage_budget"]),
			"%s pays more than its wage budget" % club_id)
		assert_lte(float(row["wage_budget"]),
			float(int(row["revenue_base"])) * 0.55 + 1.0,
			"%s budgets above 55%% of revenue" % club_id)
		assert_gte(MarketFinance.ffp_headroom(club_id), 0, "%s opens in FFP breach" % club_id)
	assert_eq(clubs, 20, "a Premier League save should fund twenty clubs")


func test_the_ledger_holds_every_money_kind_and_cash_follows_it() -> void:
	var season := _fresh("Finance Kinds")
	var club_id := _club()
	var date := season.save.current_date()
	var before := MarketFinance.cash(club_id)
	assert_true(MarketFinance.post(club_id, date, MarketFinance.KIND_FEE, -5000000, "SELLER"),
		"a fee line did not post")
	assert_eq(MarketFinance.cash(club_id), before - 5000000, "cash did not follow the fee")
	for kind in [MarketFinance.KIND_AGENT, MarketFinance.KIND_PRIZE, MarketFinance.KIND_GATE,
			MarketFinance.KIND_COMMERCIAL, MarketFinance.KIND_WAGE, MarketFinance.KIND_SOLIDARITY,
			MarketFinance.KIND_TRAINING, MarketFinance.KIND_FFP]:
		MarketFinance.post(club_id, date, kind, 1000, "check")
	for kind in MarketFinance.KINDS:
		if kind == MarketFinance.KIND_AMORTISATION:
			continue
		var row := PLDatabase.row(
			"SELECT COUNT(*) AS n FROM club_ledger WHERE club_id = ? AND kind = ?;",
			[club_id, kind])
		assert_gte(int(row.get("n", 0)), 1, "the ledger has no %s line" % kind)
	assert_false(MarketFinance.post(club_id, date, "nonsense", 1), "an unknown kind posted")
	assert_false(MarketFinance.post("", date, MarketFinance.KIND_GATE, 1), "a blank club posted")


func test_a_fee_amortises_over_its_contract_years() -> void:
	var season := _fresh("Finance Amortisation")
	var club_id := _club()
	var date := season.save.current_date()
	assert_eq(MarketFinance.amortisation(40000000, 4), 10000000,
		"forty million over four years is not ten a season")
	assert_eq(MarketFinance.amortisation(40000000), 10000000,
		"the default spread is not four years")
	var cash := MarketFinance.cash(club_id)
	var headroom := MarketFinance.ffp_headroom(club_id)
	assert_eq(MarketFinance.post_amortisation(club_id, date, 40000000, 4, "player"),
		10000000, "the amortisation row posted the wrong amount")
	assert_eq(MarketFinance.cash(club_id), cash, "amortisation moved cash")
	assert_eq(MarketFinance.ffp_headroom(club_id), headroom - 10000000,
		"amortisation did not bite the FFP measure")
	assert_eq(MarketFinance.amortisation_season(club_id), 10000000,
		"the season's amortisation sum is wrong")


func test_a_home_fixture_posts_its_gate_on_the_tick() -> void:
	var season := _fresh("Finance Gate")
	var fixture: Dictionary = season.record.fixtures.all(1)[0]
	var home := str(fixture["home_club_id"])
	LeagueSeasonSim.fixture(season, fixture)
	assert_eq(MarketFinance.tick_gates(season, season.save.current_date()), 1,
		"the tick did not post the one played home fixture")
	var line := PLDatabase.row(
		"SELECT amount FROM club_ledger WHERE club_id = ? AND kind = 'gate' LIMIT 1;", [home])
	assert_false(line.is_empty(), "a home fixture posted no gate")
	assert_gt(int(line.get("amount", 0)), 0, "the gate line is worth nothing")
	assert_eq(MarketFinance.tick_gates(season, season.save.current_date()), 0,
		"the same fixture posted its gate twice")


func test_a_month_posts_commercial_and_wage_lines_for_every_club() -> void:
	var season := _fresh("Finance Month")
	var club_id := _club()
	var date := season.save.current_date()
	var cash := MarketFinance.cash(club_id)
	var posted := MarketFinance.month(date)
	assert_eq(posted, 20, "a month posted for %d clubs" % posted)
	var commercial := PLDatabase.row(
		"SELECT amount FROM club_ledger WHERE club_id = ? AND kind = 'commercial' "
		+ "ORDER BY id DESC LIMIT 1;", [club_id])
	var wage := PLDatabase.row(
		"SELECT amount FROM club_ledger WHERE club_id = ? AND kind = 'wage' "
		+ "ORDER BY id DESC LIMIT 1;", [club_id])
	assert_gt(int(commercial.get("amount", 0)), 0, "the commercial line is worth nothing")
	assert_lt(int(wage.get("amount", 0)), 0, "the wage line does not spend")
	assert_lt(MarketFinance.cash(club_id), cash + int(commercial.get("amount", 0)),
		"the month did not spend the wage bill")


func test_the_season_end_pays_prize_money_by_place() -> void:
	var season := _fresh("Finance Prize")
	PLDatabase.execute("UPDATE league_fixture SET status = 'played', home_goals = 2, "
		+ "away_goals = 1 WHERE status <> 'played';")
	season.record.standings.recompute()
	var paid := MarketFinance.season_end(season, 1)
	assert_eq(paid, 20, "the season end paid %d clubs" % paid)
	var rows := PLDatabase.rows(
		"SELECT amount FROM club_ledger WHERE kind = 'prize' ORDER BY amount DESC;")
	assert_eq(rows.size(), 20, "no prize lines were booked")
	assert_gt(int((rows[0] as Dictionary)["amount"]),
		int((rows[rows.size() - 1] as Dictionary)["amount"]),
		"the prize curve does not pay the champion more")
	for row in PLDatabase.rows("SELECT DISTINCT season_index FROM club_ledger;"):
		assert_eq(int(row["season_index"]), 1, "a season one line carries another season")


func test_money_is_one_pound_shown_in_three_currencies() -> void:
	assert_eq(MarketCurrency.format(12345678), "£12.3M", "millions read wrong in pounds")
	assert_eq(MarketCurrency.format(450000), "£450K", "thousands read wrong in pounds")
	assert_eq(MarketCurrency.format_units(12345678), "£12,345,678", "units read wrong")
	assert_eq(MarketCurrency.format(12345678, "EUR"), "€14.4M", "euros read wrong")
	assert_eq(MarketCurrency.format(12345678, "USD"), "$15.7M", "dollars read wrong")
	assert_eq(MarketCurrency.to_base(11700000, "EUR"), 10000000,
		"an entered euro fee converted wrong")
	assert_eq(MarketCurrency.to_base(12700000, "USD"), 10000000,
		"an entered dollar fee converted wrong")
	assert_eq(MarketCurrency.code_of("XXX"), "GBP", "an unknown code fell through")


func test_the_currency_setting_never_moves_a_stored_amount() -> void:
	var path := TestScratch.file("prefs_currency_442.cfg")
	Prefs._currency_cache = ""
	assert_true(Prefs.save_currency("EUR", path), "the currency setting did not save")
	assert_eq(Prefs.load_currency(path), "EUR", "the currency setting did not read back")
	var season := _shared()
	var club_id := _club()
	var budget := MarketFinance.wage_budget(club_id)
	var cash := MarketFinance.cash(club_id)
	Prefs.save_currency("USD", path)
	assert_eq(MarketFinance.wage_budget(club_id), budget, "the setting moved the budget")
	assert_eq(MarketFinance.cash(club_id), cash, "the setting moved the cash")
	Prefs._currency_cache = ""
	assert_true(Prefs.save_currency("GBP", path), "the setting did not reset")


func test_the_club_page_reads_cash_wages_ffp_and_the_ledger_tail() -> void:
	var season := _fresh("Finance Club Page")
	var club_id := _club()
	MarketFinance.post(club_id, season.save.current_date(), MarketFinance.KIND_COMMERCIAL,
		123000, "commercial")
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var sections: Array = []
	var labels: Array = []
	for block in page.get("blocks", []):
		var entry: Dictionary = block
		if str(entry.get("k", "")) == "section":
			sections.append(str(entry.get("text", "")))
		if str(entry.get("k", "")) == "kv":
			for item in entry.get("items", []):
				labels.append(str((item as Array)[0]))
	assert_true(sections.has("FINANCES"), "the club page has no finances block")
	for label in ["CASH", "WAGE BILL", "WAGE BUDGET", "FFP HEADROOM", "REPUTATION"]:
		assert_true(labels.has(label), "the club page lost the %s line" % label)
	var tables := 0
	for block in page.get("blocks", []):
		if str((block as Dictionary).get("k", "")) == "table":
			tables += 1
	assert_gte(tables, 1, "the club page shows no ledger tail")


func test_the_bootstrap_runs_once_and_never_rewrites_a_funded_club() -> void:
	var season := _fresh("Finance Bootstrap")
	var club_id := _club()
	var cash := MarketFinance.cash(club_id)
	var again := MarketFinance.bootstrap(season.save)
	assert_true(bool(again.get("ok", false)), "a second bootstrap failed")
	assert_true(bool(again.get("skipped", false)), "a second bootstrap rewrote the envelope")
	assert_eq(MarketFinance.cash(club_id), cash, "a second bootstrap moved the cash")


func test_money_reads_a_club_s_affordability_and_reputation() -> void:
	var season := _shared()
	var club_id := _club()
	assert_true(MarketFinance.can_afford(club_id, MarketFinance.cash(club_id)),
		"a club cannot afford its own cash")
	assert_false(MarketFinance.can_afford(club_id, MarketFinance.cash(club_id) + 1),
		"a club can spend more than it holds")
	assert_gt(MarketFinance.reputation(club_id), 0, "a club holds no reputation")
	assert_eq(MarketFinance.ledger_tail(club_id).size(), 0, "a new save opens with ledger lines")
	assert_eq(MarketPurse.prize("PL", 0, 20), 0, "a prize was paid for no place")
	assert_eq(MarketPurse.prize("PL", 1, 0), 0, "a prize was paid in an empty league")
	assert_eq(MarketPurse.size("PL"), 20, "the prize curve does not read the table size")


func test_signed_and_blank_amounts_still_read() -> void:
	assert_eq(MarketCurrency.format(-450000), "-£450K", "a negative thousand reads wrong")
	assert_eq(MarketCurrency.format_units(-12345678), "-£12,345,678",
		"a negative amount reads wrong")
	assert_eq(MarketCurrency.format(0), "£0", "zero does not read")
	assert_true(Prefs.save_currency("XXX", TestScratch.file("prefs_currency_bad.cfg")),
		"an unknown currency was refused a save")
	Prefs._currency_cache = ""
	assert_true(Prefs.save_currency("GBP"), "the real setting did not reset")


func test_an_unfunded_club_reads_no_finances_block() -> void:
	var season := _shared()
	var cup_club := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'FAC' ORDER BY id LIMIT 1;").get("id", ""))
	assert_true(cup_club != "", "the seed has no cup club")
	assert_true(MarketFinance.club(cup_club).is_empty(), "a cup club holds a finance row")
	var page := WikiModel.page(WikiModel.TEAM, cup_club)
	for block in page.get("blocks", []):
		assert_ne(str((block as Dictionary).get("text", "")), "FINANCES",
			"an unfunded club reads a finances block")
