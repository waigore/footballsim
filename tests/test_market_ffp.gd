extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_ffp_449")
var CACHE_DIR := TestScratch.dir("cache_market_ffp_449")
const SEED := 6449
const DATE := "2026-08-20"

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
	assert_not_null(season, "%s was not created: %s" % [name, LeagueSave.last_error])
	opened.append(season)
	shared = null
	return season


func _shared() -> LeagueSeason:
	if shared != null and LeagueSeason.active == shared:
		return shared
	shared = _fresh("FFP Read")
	return shared


func _club() -> String:
	return str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))


func _competition(club_id: String) -> String:
	return str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[club_id]).get("competition_id", ""))


func _breach(club_id: String, season: int) -> void:
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	PLDatabase.execute(
		"INSERT INTO club_ledger (season_index, date, club_id, kind, amount, counterparty) "
		+ "VALUES (?, ?, ?, ?, ?, ?);",
		[season, DATE, club_id, MarketFinance.KIND_AMORTISATION, 200_000_000, "breach"])


func _ledger(club_id: String, season: int, revenue: int, wages: int, amortisation: int,
		agent: int) -> void:
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	var rows := [[MarketFinance.KIND_COMMERCIAL, revenue], [MarketFinance.KIND_WAGE, -wages],
		[MarketFinance.KIND_AMORTISATION, amortisation], [MarketFinance.KIND_AGENT, -agent]]
	for row in rows:
		if int(row[1]) == 0:
			continue
		PLDatabase.execute(
			"INSERT INTO club_ledger (season_index, date, club_id, kind, amount, counterparty) "
			+ "VALUES (?, ?, ?, ?, ?, ?);",
			[season, DATE, club_id, str(row[0]), int(row[1]), "check"])


func test_each_term_is_measured_on_its_own() -> void:
	var season := _fresh("FFP Terms")
	var club_id := _club()
	var index := MarketFFP.season_index()
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	MarketFinance.post(club_id, DATE, MarketFinance.KIND_COMMERCIAL, 50_000_000, "commercial")
	MarketFinance.post(club_id, DATE, MarketFinance.KIND_GATE, 20_000_000, "gate")
	MarketFinance.post(club_id, DATE, MarketFinance.KIND_PRIZE, 10_000_000, "prize")
	MarketFinance.post(club_id, DATE, MarketFinance.KIND_WAGE, -30_000_000, "squad")
	MarketFinance.post(club_id, DATE, MarketFinance.KIND_AGENT, -5_000_000, "agent")
	var am := MarketFinance.post_amortisation(club_id, DATE, 40_000_000, 4, "")
	var measured := MarketFFP.earnings(club_id, index, index)
	assert_eq(int(measured["revenue"]), 80_000_000, "revenue is not gate + commercial + prize")
	assert_eq(int(measured["wages"]), 30_000_000, "wages are not the season's wage sum")
	assert_eq(int(measured["amortisation"]), 10_000_000, "amortisation is not the fee spread")
	assert_eq(int(measured["agent"]), 5_000_000, "agent fees are not their own term")
	assert_eq(int(measured["measure"]), 80_000_000 - 30_000_000 - 10_000_000 - 5_000_000,
		"the measure is not revenue minus the three costs")


func test_season_one_is_monitored_and_never_sanctioned() -> void:
	var season := _shared()
	var club_id := _club()
	assert_eq(MarketFFP.season_index(), 0, "the save does not open in season one")
	assert_true(MarketFFP.monitored(0), "season one is not monitored")
	_breach(club_id, 0)
	var status := MarketFFP.status(club_id, 0)
	assert_lt(int(status["headroom"]), 0, "a club over the line still shows headroom")
	assert_eq(str(status["state"]), MarketFFP.MONITORED, "season one carries a live sanction state")
	assert_true(bool(status["compliant"]), "season one sanctioned a non-compliant club")
	assert_false(MarketFFP.sanctioned(club_id, 0), "season one sanctioned a club")
	assert_false(MarketFFP.embargoed(club_id, 0), "season one placed an embargo")


func test_a_non_compliant_club_is_refused_an_incoming_registration() -> void:
	var season := _fresh("FFP Embargo")
	var club_id := _club()
	season.save.set_season(1, "2027-28")
	_breach(club_id, 1)
	assert_true(MarketFFP.sanctioned(club_id, 1), "the club is not over the line")
	var competition_id := _competition(club_id)
	var outsider := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "AND id NOT IN (SELECT player_id FROM player_registration WHERE competition_id = ?) "
		+ "ORDER BY ovr DESC LIMIT 1;", [club_id, competition_id]).get("id", ""))
	PLDatabase.execute("UPDATE player SET club_id = ?, homegrown_club_id = '' WHERE id = ?;",
		[club_id, outsider])
	var out := MarketRegistration.register(outsider, club_id, competition_id, "permanent", "",
		1, DATE)
	assert_false(bool(out.get("ok", false)), "an embargoed club registered a signing")
	assert_eq(str(out.get("code", "")), MarketDealRules.FFP, "the refusal does not name FFP")
	season.save.set_season(0, "2026-27")


func test_the_booked_points_are_applied_exactly_once_at_the_next_table_start() -> void:
	var season := _fresh("FFP Deduction")
	var club_id := _club()
	var competition_id := _competition(club_id)
	var next := 1
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	_breach(club_id, next)
	assert_true(MarketFFP.sanctioned(club_id, next), "the club is not over the line")
	assert_true(MarketFFP.book_breach(club_id, competition_id, DATE, next),
		"the breach booked no deduction")
	var pending := MarketFFP.pending(club_id, competition_id, next + 1)
	assert_false(pending.is_empty(), "the deduction is not booked for the next season")
	assert_eq(int(pending.get("points", 0)), MarketFFP.deduction_points(),
		"the booked points are not the rule's deduction")
	assert_eq(MarketFFP.apply_at_table_start(competition_id, next + 1), 1,
		"the table start did not apply the booked points")
	var label := season.save.season_label()
	season.save.set_season(next + 1, label)
	season.record.standings.recompute()
	var points := int(PLDatabase.row(
		"SELECT points FROM league_table WHERE club_id = ? AND competition_id = ?;",
		[club_id, competition_id]).get("points", 0))
	assert_eq(points, -MarketFFP.deduction_points(), "the table did not carry the deduction")
	season.record.standings.recompute()
	var again := int(PLDatabase.row(
		"SELECT points FROM league_table WHERE club_id = ? AND competition_id = ?;",
		[club_id, competition_id]).get("points", 0))
	assert_eq(again, -MarketFFP.deduction_points(), "a recompute applied the deduction twice")
	assert_eq(MarketFFP.apply_at_table_start(competition_id, next + 1), 0,
		"a second table start re-applied the deduction")
	season.save.set_season(0, label)


func test_the_sheet_headroom_is_the_value_the_commit_check_uses() -> void:
	var season := _fresh("FFP Headroom")
	var club_id := _club()
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	var sheet := MarketFinance.ffp_headroom(club_id)
	var measure := MarketFFP.headroom(club_id)
	assert_eq(sheet, measure, "the sheet and the measure disagree")
	var fee := sheet + 10_000_000
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var shown := _kv_value(page, "FFP HEADROOM")
	assert_true(shown != "", "the club page lost its FFP headroom")
	var verdict := MarketFFP.check_at_commit({"to_club_id": club_id, "fee": fee, "years": 1,
		"wage": 0, "agent_fee": 0}, {})
	assert_false(bool(verdict.get("ok", false)), "the commit check passed over the headroom")
	var over := MarketFFP.check_at_commit({"to_club_id": club_id, "fee": fee, "years": 1,
		"wage": 0, "agent_fee": 0}, {"force": true})
	assert_true(bool(over.get("ok", false)), "force did not skip the FFP test")
	assert_eq(str(over.get("note", "")), "ffp_override", "a forced deal was not logged")


func test_a_uefa_entrant_is_not_assessed_against_a_uefa_rule_set() -> void:
	var season := _fresh("FFP Domestic")
	var club_id := _club()
	var index := MarketFFP.season_index()
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	var as_domestic := MarketFFP.measure(club_id, index)
	assert_eq(str(as_domestic["association"]), "ENG", "the domestic measure lost its association")
	assert_eq(int(as_domestic["allowed"]),
		MarketFFP.allowed_loss("ENG"), "the domestic threshold is not the association's")
	var ucl := MarketFFP.allowed_loss("Europe")
	assert_eq(ucl, MarketRules.count("ffp", "default_allowed_loss", 45000000),
		"a UEFA association was given its own threshold")


func test_the_ffp_verb_measures_embargoes_and_deducts_with_no_deal_engine() -> void:
	var script: Script = load("res://tools/market_sim/ffp.gd")
	assert_not_null(script, "the ffp verb does not load")
	for inject in ["none", "embargo", "deduction"]:
		var out: Dictionary = script.run({"inject": inject})
		assert_true(bool(out.get("ok", false)),
			"the ffp verb failed on %s: %s" % [inject, JSON.stringify(out)])
		assert_eq(str(out.get("injected", "")), inject, "the verb lost its injection name")
		assert_eq(str(out.get("state", "")), MarketFFP.MONITORED,
			"the verb did not open in a monitored season")


func test_a_blocked_deal_names_ffp_and_the_sheet_shows_headroom() -> void:
	var season := _fresh("FFP Deal")
	var from := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1;").get("id", ""))
	var to := str(PLDatabase.row(
		"SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id LIMIT 1 OFFSET 1;").get("id", ""))
	season.save.set_season(1, "2027-28")
	_breach(to, 1)
	PLDatabase.execute("UPDATE club_finance SET cash = 500000000 WHERE club_id = ?;", [to])
	assert_true(MarketFFP.sanctioned(to, 1), "the buyer is not over the line")
	var player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;", [from]).get("id", ""))
	var contract := MarketDealRecords.active_contract(player)
	var terms := {"fee": 1_000_000, "wage": int(contract.get("wage", 5000)), "years": 2,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}
	var deal := str(MarketDeals.propose(season, from, to, player, terms, DATE).get("deal", ""))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_false(bool(agreed.get("ok", false)), "an embargoed club agreed a deal")
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.FFP, "the deal does not name FFP")
	var sheet := _kv_value(WikiModel.page(WikiModel.TEAM, to), "FFP HEADROOM")
	assert_true(sheet != "", "the finance sheet shows no headroom")
	season.save.set_season(0, "2026-27")


func test_the_month_tick_embargoes_and_books() -> void:
	var season := _fresh("FFP Tick")
	var club_id := _club()
	var competition_id := _competition(club_id)
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	_breach(club_id, 1)
	season.save.set_season(1, "2027-28")
	var out := MarketFFP.tick(season, DATE)
	assert_gte(int(out.get("embargoed", 0)), 1, "the month tick found no embargoed club")
	assert_gte(int(out.get("booked", 0)), 1, "the month tick booked no deduction")
	var pending := MarketFFP.pending(club_id, competition_id, 2)
	assert_false(pending.is_empty(), "the tick did not book a next-season deduction")
	season.save.set_season(0, "2026-27")


func test_a_monitored_season_tick_books_nothing() -> void:
	var season := _fresh("FFP Tick Season One")
	var club_id := _club()
	PLDatabase.execute("DELETE FROM club_ledger WHERE club_id = ?;", [club_id])
	_breach(club_id, 0)
	var out := MarketFFP.tick(season, DATE)
	assert_eq(int(out.get("embargoed", 0)), 0, "season one placed an embargo on a tick")
	assert_eq(int(out.get("booked", 0)), 0, "season one booked a deduction on a tick")


func _kv_value(page: Dictionary, label: String) -> String:
	for block in page.get("blocks", []):
		if str((block as Dictionary).get("k", "")) != "kv":
			continue
		for item in (block as Dictionary).get("items", []):
			if str((item as Array)[0]) == label:
				return str((item as Array)[1])
	return ""
