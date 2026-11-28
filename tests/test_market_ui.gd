extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_ui_453")
var CACHE_DIR := TestScratch.dir("cache_market_ui_453")
var FIXTURE := TestScratch.dir("fixture_market_ui_453").path_join("world.sqlite")
const SEED := 7453
const DATE := "2026-08-20"
const CLOSED := "2026-12-20"

var current: LeagueSeason = null


func before_all() -> void:
	PLDatabase.cache_dir = CACHE_DIR
	LeagueSave.dir = SAVE_DIR
	_clean()
	PLDatabase.reset()
	PLRepository.shared().invalidate()
	var script: Script = load("res://tools/market_sim/ui_fixture.gd")
	var built: Dictionary = script.run({"out": FIXTURE, "seed": str(SEED), "deals": "8"})
	assert_true(bool(built.get("ok", false)), "the ui-fixture could not be written")


func after_all() -> void:
	_close()
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _close() -> void:
	if current != null:
		current.close()
		current = null


func _open() -> LeagueSeason:
	_close()
	current = LeagueSeason.open(FIXTURE)
	assert_not_null(current, "the ui-fixture save did not open")
	return current


func _clubs() -> Array:
	var out: Array = []
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;"):
		out.append(str(row["id"]))
	return out


func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[club_id]).get("id", ""))


func _terms(player_id: String, fee: int = 100_000, wage: int = -1) -> Dictionary:
	var current_wage := int(MarketDealRecords.active_contract(player_id).get("wage", 5000))
	return {"fee": fee, "wage": current_wage if wage < 0 else wage, "years": 3,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}


func _propose(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary, date: String = DATE) -> String:
	return str(MarketDeals.propose(season, from, to, player, terms, date).get("deal", ""))


func _registration(player_id: String, club_id: String) -> Dictionary:
	var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return MarketDealRecords.registration(player_id, str(club.get("competition_id", "")))


func test_force_skips_consent_cash_and_ffp_but_not_the_window() -> void:
	var season := _open()
	var clubs := _clubs()
	var closed_from := str(clubs[0])
	var closed_player := _player_at(closed_from)
	var closed := _propose(season, closed_from, str(clubs[1]), closed_player,
		_terms(closed_player, 100_000), CLOSED)
	var refused := MarketDeals.force(closed, CLOSED)
	assert_eq(str(refused.get("state", "")), MarketDealRecords.FAILED,
		"force signed through a closed window")
	assert_eq(str(refused.get("reason", "")), MarketDealRules.WINDOW_CLOSED,
		"the closed-window force lost its code")

	var from := str(clubs[2])
	var to := str(clubs[3])
	var player := _player_at(from)
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	var forced := MarketDeals.force(_propose(season, from, to, player,
		_terms(player, 999_000_000, maxi(wage - 1000, 1))), DATE)
	assert_eq(str(forced.get("state", "")), MarketDealRecords.SIGNED,
		"force did not skip consent, cash and FFP: %s" % str(forced.get("reason", "")))
	assert_eq(str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;",
		[player]).get("club_id", "")), to, "the forced player did not move")


func test_a_forced_signing_past_a_full_list_reads_ineligible() -> void:
	var season := _open()
	var clubs := _clubs()
	var seller := str(clubs[4])
	var buyer := str(clubs[5])
	var competition := str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[buyer]).get("competition_id", ""))
	var used := MarketLists.slots_used(buyer, competition)
	var spare: Array = []
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id <> ? AND id NOT IN "
			+ "(SELECT player_id FROM player_registration WHERE competition_id = ?) LIMIT ?;",
			[buyer, competition, maxi(MarketLists.SLOTS - used, 0)]):
		spare.append(str(row["id"]))
	for id in spare:
		PLDatabase.execute(
			"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, "
			+ "kind, state, reason, deal_id, season_index, u21_exempt) "
			+ "VALUES (?, ?, ?, 'permanent', 'registered', '', '', 0, 0);",
			[id, competition, buyer])
	assert_gte(MarketLists.slots_used(buyer, competition), MarketLists.SLOTS,
		"the probe did not fill the list")
	var player := _player_at(seller)
	var out := MarketDeals.force(_propose(season, seller, buyer, player, _terms(player), DATE), DATE)
	assert_eq(str(out.get("state", "")), MarketDealRecords.SIGNED,
		"a full list voided the forced deal: %s" % str(out.get("reason", "")))
	var registration := _registration(player, buyer)
	assert_eq(str(registration.get("state", "")), "ineligible",
		"a full-list signing reads as registered")
	assert_eq(str(registration.get("reason", "")), "list_full",
		"the registration lost its list code")


func test_block_kills_the_instance_and_vetoes_the_buyer_for_the_window() -> void:
	var season := _open()
	var clubs := _clubs()
	var from := str(clubs[6])
	var buyer := str(clubs[7])
	var other := str(clubs[8])
	var player := _player_at(from)
	var deal := _propose(season, from, buyer, player, _terms(player))
	MarketDeals.agree(deal, DATE)
	var blocked := MarketDeals.block(deal, DATE, "veto")
	assert_eq(str(blocked.get("state", "")), MarketDealRecords.BLOCKED, "the veto did not land")
	var again := MarketDeals.agree(_propose(season, from, buyer, player, _terms(player)), DATE)
	assert_eq(str(again.get("reason", "")), MarketDealRules.BLOCKED,
		"the same buyer escaped the veto")
	var else_where := MarketDeals.agree(_propose(season, from, other, player, _terms(player)), DATE)
	assert_ne(str(else_where.get("reason", "")), MarketDealRules.BLOCKED,
		"another buyer inherited the veto")


func test_rewrite_reruns_every_validator_and_can_fail() -> void:
	var season := _open()
	var clubs := _clubs()
	var from := str(clubs[9])
	var to := str(clubs[10])
	var player := _player_at(from)
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	var cut := _terms(player, 100_000, maxi(wage - 1000, 1))
	var deal := _propose(season, from, to, player, cut)
	var refused := MarketDeals.agree(deal, DATE)
	assert_eq(str(refused.get("reason", "")), MarketDealRules.CONSENT, "the cut was not refused")
	var again := MarketDeals.rewrite(deal, cut, DATE)
	assert_eq(str(again.get("reason", "")), MarketDealRules.CONSENT,
		"the rewrite did not re-run the consent check")
	var fixed := MarketDeals.rewrite(deal, _terms(player, 100_000, wage), DATE)
	assert_ne(str(fixed.get("reason", "")), MarketDealRules.CONSENT,
		"the rewritten terms still failed consent")


class FakeScreen extends RefCounted:
	const MODE_HUB := LeagueScreen.MODE_HUB
	const MODE_WIZARD := LeagueScreen.MODE_WIZARD
	const MODE_LOAD := LeagueScreen.MODE_LOAD
	const MODE_TRANSFERS := LeagueScreen.MODE_TRANSFERS
	const MODE_DEAL := LeagueScreen.MODE_DEAL
	const MODE_NEWS := LeagueScreen.MODE_NEWS
	const MODE_CUP_DRAW := LeagueScreen.MODE_CUP_DRAW
	var season: LeagueSeason = null
	var mode := LeagueScreen.MODE_TRANSFERS
	var touch := false
	var deal_id := ""
	var market_view := ""
	var month := ""
	var day := ""
	var days_cache := {}
	var day_fixtures: Array = []
	var report: Dictionary = {}
	var roundup: Array = []
	var report_back := "hub"
	var interest_query := ""
	var sys := {}
	var cup_focus := ""
	var cups_round := ""
	var draw_state := {}
	var load_from := "menu"
	var body = null
	var focus := LeagueFieldFocus.new()
	var delete := LeagueDelete.new()
	var nav := LeagueNavStack.new()
	var panel := LeaguePanel.new()
	var refreshes := 0
	func _init(owner: LeagueSeason) -> void:
		season = owner
	func refresh() -> void:
		refreshes += 1
	func push_page() -> void:
		nav.push(LeagueNavStack.snapshot(self))
	func delete_confirm_open() -> bool:
		return false


func _fake(season: LeagueSeason) -> FakeScreen:
	return FakeScreen.new(season)


func _signed_deal(index: int = 0) -> Dictionary:
	var rows := PLDatabase.rows(
		"SELECT * FROM deal WHERE state = 'signed' ORDER BY fee DESC, id;")
	if rows.is_empty():
		return {}
	return rows[clampi(index, 0, rows.size() - 1)]


func test_the_hub_surfaces_windows_news_free_agents_and_movers() -> void:
	var season := _open()
	var fake := _fake(season)
	var view := LeagueMarketView.hub(fake)
	assert_eq((view.get("windows", []) as Array).size(), 4, "the hub lost an association band")
	assert_false((view.get("news", []) as Array).is_empty(), "the hub carried no news")
	assert_false((view.get("free_agents", []) as Array).is_empty(), "the hub carried no free agents")
	assert_false((view.get("movers", []) as Array).is_empty(), "the hub carried no top movers")
	for vp in [Vector2(1600, 900), Vector2(913, 411)]:
		var items: Array = LeagueTransferSheet.new().layout(vp, view)
		var kinds := {}
		for item in items:
			kinds[str(item["kind"])] = true
		for want in ["window", "market_row", "free_agent", "mover", "button"]:
			assert_true(kinds.has(want), "the hub lost its %s row at %s" % [want, vp])


func test_the_inspector_names_the_state_the_reason_and_the_god_doors() -> void:
	var season := _open()
	var fake := _fake(season)
	var signed := _signed_deal(0)
	assert_false(signed.is_empty(), "the fixture holds no signed deal")
	fake.deal_id = str(signed["id"])
	var view := LeagueMarketView.deal(fake)
	assert_eq(str(view.get("state", "")), MarketDealRecords.SIGNED, "the inspector lost the state")
	assert_false(bool(view.get("can_act", true)), "a signed deal still offers god doors")
	var vp := Vector2(1600, 900)
	var items: Array = LeagueDealSheet.new().layout(vp, view)
	var doors := 0
	var terms := 0
	for item in items:
		if str(item["id"]).begins_with("god:"):
			doors += 1
			assert_true(bool(item.get("disabled", false)), "a signed deal left a god door live")
		if str(item["kind"]) == "term":
			terms += 1
	assert_eq(doors, 3, "the inspector lost FORCE, BLOCK or REWRITE")
	assert_gte(terms, 5, "the inspector itemised no terms")

	var failed := PLDatabase.row(
		"SELECT * FROM deal WHERE state = 'failed' ORDER BY id LIMIT 1;")
	if not failed.is_empty():
		fake.deal_id = str(failed["id"])
		var fail_view := LeagueMarketView.deal(fake)
		assert_eq(str(fail_view.get("state", "")), MarketDealRecords.FAILED,
			"the inspector lost a failed state")
		assert_true(str(fail_view.get("reason", "")) != "",
			"the inspector lost the reason code a deal failed with")


func test_a_closed_window_disables_the_panel_with_its_reason_and_opening_date() -> void:
	var season := _open()
	var fake := _fake(season)
	var closed := "2027-06-01"
	var club := str(PLDatabase.row(
		"SELECT club_id FROM club_finance ORDER BY club_id LIMIT 1;").get("club_id", ""))
	var state := MarketWindows.state(closed, "ENG")
	var view := {"empty": false, "deal_id": "x", "deal": {"to_club_id": club, "player_id": "",
		"from_club_id": "", "fee": 1, "wage": 1, "years": 1, "state": "proposed"},
		"state": "proposed", "reason": "", "terms": [], "checks": [], "timeline": [],
		"window": state, "free_agent": false, "can_act": false, "touch": false,
		"date": closed}
	var items: Array = LeagueDealSheet.new().layout(Vector2(1600, 900), view)
	var note := ""
	for item in items:
		if str(item["kind"]) == "note" and str(item.get("label", "")).contains("WINDOW"):
			note = str(item["label"])
		if str(item["id"]).begins_with("god:"):
			assert_true(bool(item.get("disabled", false)), "a closed window left a god door live")
	assert_true(note.contains("WINDOW IS CLOSED"), "the closed panel names no reason")
	assert_false(bool(state.get("open", true)), "the probe window is open")
	assert_true(str(state.get("opens_on", "")) != "", "the closed panel names no opening date")


func test_every_market_surface_is_reachable_from_the_nav_and_returns() -> void:
	var season := _open()
	var fake := _fake(season)
	var found := false
	for item in LeaguePanel.ITEMS:
		if str(item["id"]) == "nav:transfers":
			found = true
	assert_true(found, "the left panel has no TRANSFERS row")
	for mode in [LeagueScreen.MODE_TRANSFERS, LeagueScreen.MODE_DEAL, LeagueScreen.MODE_NEWS]:
		assert_false(LeagueView.pose(mode).is_empty(), "the %s mode has no sheet" % mode)
	LeaguePanelDoors.nav(fake, "transfers")
	assert_eq(fake.mode, LeagueScreen.MODE_TRANSFERS, "the panel did not open the hub")
	var deal := _signed_deal(0)
	LeagueDoors.open_deal(fake, str(deal["id"]))
	assert_eq(fake.mode, LeagueScreen.MODE_DEAL, "the hub did not open the inspector")
	assert_eq(fake.nav.depth(), 1, "the inspector did not push a page")
	LeagueDoors.back(fake)
	assert_eq(fake.mode, LeagueScreen.MODE_TRANSFERS, "BACK did not return to the hub")
	assert_eq(fake.nav.depth(), 0, "BACK did not pop the page")
	LeagueDoors.go(fake, LeagueScreen.MODE_NEWS)
	assert_eq(fake.mode, LeagueScreen.MODE_NEWS, "the feed did not open")
	LeagueDoors.back(fake)
	assert_eq(fake.mode, LeagueScreen.MODE_TRANSFERS, "the feed did not return to the hub")


func test_a_phone_market_sheet_keeps_every_door_finger_sized_and_scrolls() -> void:
	var season := _open()
	var fake := _fake(season)
	fake.touch = true
	var hub := LeagueMarketView.hub(fake)
	var vp := Vector2(913, 411)
	var items: Array = LeagueTransferSheet.new().layout(vp, hub)
	var bottom := 0.0
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		bottom = maxf(bottom, rect.end.y)
		if kind in ["button", "window", "market_row", "free_agent", "mover"]:
			assert_gte(rect.size.y, UiChrome.TAP_H, "%s is under a finger" % kind)
		if kind in ["window", "market_row", "free_agent", "mover"]:
			assert_true(str(item["id"]) != "", "a %s row is not a door" % kind)
	assert_gt(bottom, vp.y, "a full phone market sheet does not scroll")
	var deal := _signed_deal(0)
	fake.deal_id = str(deal["id"])
	for item in LeagueDealSheet.new().layout(vp, LeagueMarketView.deal(fake)):
		if str(item["id"]).begins_with("god:"):
			assert_gte((item["rect"] as Rect2).size.y, UiChrome.TAP_H, "a god door is under a finger")


func test_the_market_panel_exposes_no_club_context_inbox_or_tasks() -> void:
	var season := _open()
	var fake := _fake(season)
	fake.deal_id = str(_signed_deal(0)["id"])
	var hub := LeagueMarketView.hub(fake)
	var deal := LeagueMarketView.deal(fake)
	for view in [hub, deal]:
		for banned in ["my_club", "inbox", "tasks", "manager", "career"]:
			assert_false((view as Dictionary).has(banned), "the market exposes %s" % banned)
	for item in LeaguePanel.ITEMS:
		assert_false(str(item["label"]).to_lower().contains("my club"),
			"the panel offers a club-manager row")


func test_the_fixture_save_is_what_the_market_suites_open() -> void:
	assert_true(FileAccess.file_exists(FIXTURE), "the ui-fixture was not written")
	var season := _open()
	assert_true(season.save.theme_ready(), "the ui-fixture is not a market save")
	assert_gt(int(PLDatabase.row("SELECT COUNT(*) AS n FROM deal;").get("n", 0)), 0,
		"the ui-fixture holds no deals")
	assert_gt(MarketNews.count(season.save.season_index()), 0, "the ui-fixture holds no news")
	var script: Script = load("res://tools/market_sim/ui_fixture.gd")
	var out := TestScratch.dir("fixture_market_ui_453_second").path_join("world.sqlite")
	var again: Dictionary = script.run({"out": out, "seed": str(SEED), "deals": "4"})
	assert_true(bool(again.get("ok", false)), "the ui-fixture refused a second write")
	assert_true(FileAccess.file_exists(out), "the second ui-fixture was not written")


func test_the_club_and_player_pages_read_the_list_and_contract() -> void:
	var season := _open()
	var buyer := str(PLDatabase.row(
		"SELECT club_id FROM player_registration WHERE state = 'registered' "
		+ "ORDER BY player_id LIMIT 1;").get("club_id", ""))
	var team := WikiTeam.page(buyer)
	var has_squad := false
	for block in team.get("blocks", []):
		if str((block as Dictionary).get("k", "")) == "section" \
				and str((block as Dictionary).get("text", "")) == "SQUAD LIST":
			has_squad = true
	assert_true(has_squad, "the club page carries no SQUAD LIST block")
	var player_row := PLDatabase.row(
		"SELECT player_id FROM player_registration WHERE club_id = ? AND state = 'registered' "
		+ "AND u21_exempt = 0 LIMIT 1;", [buyer])
	if player_row.is_empty():
		return
	var page := WikiPlayer.page(str(player_row["player_id"]))
	var has_registration := false
	for block in page.get("blocks", []):
		if str((block as Dictionary).get("k", "")) != "kv":
			continue
		for pair in (block as Dictionary).get("items", []):
			if str((pair as Array)[0]) == "REGISTRATION":
				has_registration = true
	assert_true(has_registration, "the player page carries no registration state")
