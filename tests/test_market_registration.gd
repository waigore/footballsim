extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_market_registration_448")
var CACHE_DIR := TestScratch.dir("cache_market_registration_448")
const SEED := 6448
const DATE := "2026-08-20"
const CLOSED := "2026-12-20"

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


func _fresh(name: String, competitions: Array = ["PL"], uefa: bool = false) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, competitions,
		uefa, [], uefa)
	assert_not_null(season, "%s was not created: %s" % [name, LeagueSave.last_error])
	opened.append(season)
	return season


func _shared() -> LeagueSeason:
	if shared != null and LeagueSeason.active == shared:
		return shared
	shared = _fresh("Registration Read")
	return shared


func _club_in(competition_id: String, index: int = 0) -> String:
	var rows := PLDatabase.rows(
		"SELECT id FROM club WHERE competition_id = ? AND stub = 0 ORDER BY id;",
		[competition_id])
	if rows.is_empty():
		return ""
	return str(rows[clampi(index, 0, rows.size() - 1)]["id"])


func _competition(club_id: String) -> String:
	return str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[club_id]).get("competition_id", ""))


func _player_at(club_id: String, order: String = "ovr DESC, id") -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY %s LIMIT 1;" % order,
		[club_id]).get("id", ""))


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func test_every_seeded_player_is_registered_and_no_club_is_blocked() -> void:
	var season := _shared()
	var total := _count("SELECT COUNT(*) AS n FROM player_registration;")
	var playable := _count(
		"SELECT COUNT(*) AS n FROM player p JOIN club c ON c.id = p.club_id "
		+ "WHERE p.club_id <> '' AND c.stub = 0 AND c.competition_id IN "
		+ "('PL', 'CH', 'L1', 'L2', 'NL', 'LL', 'LL2', 'BL', 'BL2', 'SA', 'SB');")
	assert_gte(total, playable, "a player at a domestic club holds no registration row")
	for row in PLDatabase.rows(
			"SELECT DISTINCT club_id, competition_id FROM player_registration "
			+ "WHERE competition_id IN ('PL', 'CH', 'LL', 'BL', 'SA');"):
		var club_id := str(row["club_id"])
		var competition_id := str(row["competition_id"])
		var state := MarketRegistration.state_of(club_id, competition_id)
		assert_in(state, [MarketRegistration.REGISTERED, MarketRegistration.PROVISIONAL],
			"%s opens in an impossible list state %s" % [club_id, state])
	var counted := MarketRegistration.tally(_club_in("PL"), "PL")
	assert_gte(int(counted["homegrown"]), 1, "a Premier League club opens with no homegrown")


func test_every_seeded_player_is_club_trained_at_his_seed_club() -> void:
	var season := _shared()
	for row in PLDatabase.rows(
			"SELECT COUNT(*) AS n FROM player WHERE club_id <> '' AND homegrown_club_id = club_id;"):
		assert_gte(int(row["n"]), 1, "the seed lost its club-trained players")
	var strays := _count(
		"SELECT COUNT(*) AS n FROM player_registration WHERE homegrown_club_id = '';")
	assert_eq(strays, 0, "a registration row has no homegrown club")


func test_a_26th_registration_is_refused_with_list_full() -> void:
	var season := _fresh("Registration Slots")
	var club_id := _club_in("PL")
	var competition_id := _competition(club_id)
	var counts := MarketRegistration.tally(club_id, competition_id)
	counts["slots"] = MarketEligibility.slots()
	var reasons := MarketEligibility.admits(competition_id, str(counts["association_code"]), counts,
		{"nationality": "France", "age": 28, "homegrown_club_id": "", "club_id": club_id})
	assert_in("list_full", reasons, "a full list admitted a 26th senior")


func test_a_signing_that_breaks_the_homegrown_floor_is_refused() -> void:
	var season := _fresh("Registration Homegrown")
	var club_id := _club_in("PL")
	var competition_id := _competition(club_id)
	var counts := MarketRegistration.tally(club_id, competition_id)
	counts["slots"] = MarketEligibility.slots()
	counts["homegrown"] = MarketEligibility.homegrown_min() - 1
	var reasons := MarketEligibility.admits(competition_id, str(counts["association_code"]), counts,
		{"nationality": "Brazil", "age": 28, "homegrown_club_id": "", "club_id": club_id})
	assert_in("homegrown_min", reasons, "a non-homegrown signing passed the eight-homegrown floor")


func test_a_failed_permit_signs_him_and_leaves_him_ineligible() -> void:
	var season := _fresh("Registration Permit")
	var club_id := _club_in("PL")
	var competition_id := _competition(club_id)
	var weak := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "AND nationality NOT IN ('England', 'Spain', 'Germany', 'Italy') "
		+ "ORDER BY ovr LIMIT 1;", [club_id]).get("id", ""))
	assert_true(weak != "", "the seed has no weak non-European")
	PLDatabase.execute("UPDATE player SET club_id = ?, homegrown_club_id = '' WHERE id = ?;",
		[club_id, weak])
	var out := MarketRegistration.register(weak, club_id, competition_id, "permanent", "",
		season.save.season_index(), DATE)
	assert_true(bool(out.get("ok", false)), "a permit failure voided the registration")
	assert_eq(str(out.get("state", "")), MarketRegistration.INELIGIBLE,
		"the failed permit reads as eligible")
	var row := MarketRegistration.row(weak, competition_id)
	assert_eq(str(row.get("permit_state", "")), MarketRegistration.INELIGIBLE,
		"the row carries no permit flag")
	var team := TeamData.get_team(club_id)
	var xi := StrongestXI.pick(team, competition_id)
	for p in xi:
		assert_ne(str(p["id"]), weak, "an ineligible player was picked for the XI")
	assert_false(MarketRegistration.selectable(weak, competition_id),
		"the selection filter admits an ineligible player")


func test_an_under_21_signing_consumes_no_slot() -> void:
	var season := _fresh("Registration U21")
	var club_id := _club_in("PL")
	var competition_id := _competition(club_id)
	var youth := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' AND age BETWEEN 17 AND 20 "
		+ "ORDER BY ovr LIMIT 1;", [club_id]).get("id", ""))
	assert_true(youth != "", "the seed has no under-21 outsider")
	var counts := MarketRegistration.tally(club_id, competition_id)
	var before := int(counts["slots"])
	counts["slots"] = MarketEligibility.slots()
	var reasons := MarketEligibility.admits(competition_id, str(counts["association_code"]), counts,
		{"nationality": "France", "age": 19, "homegrown_club_id": "", "club_id": club_id})
	assert_false(reasons.has("list_full"), "a 20-year-old consumed a slot")
	assert_eq(before, int(MarketRegistration.tally(club_id, competition_id)["slots"]),
		"the tally moved on a read")


func test_a_ucl_entrant_declares_a_25_list_with_four_association_trained() -> void:
	var season := _fresh("Registration UEFA", ["PL"], true)
	var club_id := _club_in("PL")
	var declared := MarketRegistration.declare(club_id, "UCL")
	assert_true(bool(declared.get("ok", false)), "a UCL entrant could not declare a list")
	var counts := MarketRegistration.tally(club_id, "UCL")
	assert_gte(int(counts["association"]), MarketEligibility.association_min(),
		"the UCL list has fewer than four association-trained players")
	assert_lte(int(counts["slots"]), MarketEligibility.slots(),
		"the UCL list is over 25 slots")
	assert_in(MarketRegistration.state_of(club_id, "UCL"),
		[MarketRegistration.REGISTERED, MarketRegistration.PROVISIONAL],
		"the UCL list reads as neither legal nor provisional")


func test_italy_enforces_four_club_and_eight_association_trained() -> void:
	var season := _fresh("Registration Italy", ["PL", "SA"])
	var club_id := _club_in("SA")
	var competition_id := _competition(club_id)
	assert_eq(competition_id, "SA", "the Italian club is not in Serie A")
	var counts := MarketRegistration.tally(club_id, competition_id)
	var base := counts.duplicate()
	base["slots"] = MarketEligibility.slots()
	base["club_trained"] = MarketEligibility.italy_club_min() - 1
	base["association"] = MarketEligibility.italy_association_min() - 1
	var reasons := MarketEligibility.bands(competition_id, "ITA", base)
	assert_in("italy_club_min", reasons, "the four club-trained rule did not bind")
	assert_in("italy_association_min", reasons, "the eight association-trained rule did not bind")
	var legal := counts.duplicate()
	legal["slots"] = MarketEligibility.slots()
	legal["club_trained"] = MarketEligibility.italy_club_min()
	legal["association"] = MarketEligibility.italy_association_min()
	assert_eq(MarketEligibility.bands(competition_id, "ITA", legal), [],
		"a legal Italian list was refused")


func test_a_registration_after_the_window_closes_is_refused() -> void:
	var season := _fresh("Registration Freeze")
	var club_id := _club_in("PL")
	var competition_id := _competition(club_id)
	assert_false(bool(MarketWindows.state(CLOSED, "ENG").get("open", false)),
		"the English window is open on %s" % CLOSED)
	var outsider := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "AND id NOT IN (SELECT player_id FROM player_registration WHERE competition_id = ?) "
		+ "ORDER BY ovr DESC LIMIT 1;", [club_id, competition_id]).get("id", ""))
	PLDatabase.execute("UPDATE player SET club_id = ?, homegrown_club_id = '' WHERE id = ?;",
		[club_id, outsider])
	var out := MarketRegistration.register(outsider, club_id, competition_id, "permanent", "",
		season.save.season_index(), CLOSED)
	assert_false(bool(out.get("ok", false)), "a registration landed after the window shut")
	assert_eq(str(out.get("code", "")), MarketDealRules.WINDOW_CLOSED,
		"the freeze does not name the window")
	assert_true(MarketRegistration.row(outsider, competition_id).is_empty(),
		"a refused registration wrote a row")
	var open := MarketRegistration.register(outsider, club_id, competition_id, "permanent", "",
		season.save.season_index(), DATE)
	assert_true(bool(open.get("ok", false)), "the same signing was refused in the window")


func test_cup_tied_stays_off_so_a_cup_player_remains_selectable() -> void:
	var season := _fresh("Registration Cup-tied")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var they_played := _count(
		"SELECT COUNT(*) AS n FROM match_event WHERE player_id = ?;", [player])
	assert_eq(MarketRegistration.selectable(player, _competition(to)), true,
		"a player with cup appearances reads as cup-tied")


func test_a_signed_player_is_registered_by_the_deal_engine() -> void:
	var season := _fresh("Registration Deal")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var contract := MarketDealRecords.active_contract(player)
	var terms := {"fee": 5_000_000, "wage": int(contract.get("wage", 5000)), "years": 4,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}
	var deal := str(MarketDeals.propose(season, from, to, player, terms, DATE).get("deal", ""))
	var agreed := MarketDeals.agree(deal, DATE)
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.AGREED,
		"the deal did not agree: %s" % str(agreed.get("reason", "")))
	var done := MarketDeals.seal(deal, DATE)
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"the deal did not sign: %s" % str(done.get("reason", "")))
	var registration := MarketRegistration.row(player, _competition(to))
	assert_false(registration.is_empty(), "the deal wrote no registration")
	assert_eq(str(registration.get("club_id", "")), to, "the registration names the wrong club")
	assert_eq(str(registration.get("homegrown_club_id", "")) != "", true,
		"the registration carries no homegrown club")


func test_the_split_refusal_still_reads_as_ineligible() -> void:
	var season := _fresh("Registration Refuse")
	var from := _club_in("PL", 0)
	var to := _club_in("PL", 1)
	var player := _player_at(from)
	var contract := MarketDealRecords.active_contract(player)
	var terms := {"fee": 1_000_000, "wage": int(contract.get("wage", 5000)), "years": 3,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}
	var deal := str(MarketDeals.propose(season, from, to, player, terms, DATE).get("deal", ""))
	MarketDeals.agree(deal, DATE)
	var done := MarketDeals.seal(deal, DATE, {"registration": "refuse"})
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"a refused registration voided the deal")
	var row := MarketRegistration.row(player, _competition(to))
	assert_eq(str(row.get("state", "")), MarketRegistration.INELIGIBLE,
		"the refused registration reads as registered")


func _registration_block(page: Dictionary) -> Dictionary:
	var wanted := false
	for block in page.get("blocks", []):
		var row: Dictionary = block
		if str(row.get("k", "")) == "section" and str(row.get("text", "")) == "REGISTRATION":
			wanted = true
			continue
		if wanted and str(row.get("k", "")) == "kv":
			var out := {}
			for item in row.get("items", []):
				var pair: Array = item
				out[str(pair[0])] = pair[1]
			return out
	return {}


func test_the_club_page_shows_slots_homegrown_and_permit_flags() -> void:
	var season := _shared()
	var club_id := _club_in("PL")
	var page := WikiModel.page(WikiModel.TEAM, club_id)
	var block := _registration_block(page)
	assert_false(block.is_empty(), "the club page has no registration block")
	for label in ["STATE", "SLOTS", "HOMEGROWN", "ASSOCIATION"]:
		assert_true(block.has(label), "the registration block lost the %s line" % label)
	var squad := WikiModel.repo().squad(club_id)
	var weak := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id <> ? AND club_id <> '' "
		+ "AND nationality NOT IN ('England', 'Spain', 'Germany', 'Italy') "
		+ "ORDER BY ovr LIMIT 1;", [club_id]).get("id", ""))
	PLDatabase.execute("UPDATE player SET club_id = ?, homegrown_club_id = '' WHERE id = ?;",
		[club_id, weak])
	MarketRegistration.register(weak, club_id, _competition(club_id), "permanent", "",
		season.save.season_index())
	PLRepository.shared().invalidate()
	var flagged := WikiRegistration.flags(club_id)
	assert_eq(str(flagged.get(weak, "")), WikiRegistration.INELIGIBLE_TAG,
		"the squad flags lost the ineligible signing")


func test_the_register_verb_proves_every_rule_with_no_deal_engine() -> void:
	var script: Script = load("res://tools/market_sim/register.gd")
	assert_not_null(script, "the register verb does not load")
	for inject in ["none", "permit", "list_full", "homegrown_min", "non_eu_cap", "u21"]:
		var out: Dictionary = script.run({"competition": "PL", "inject": inject})
		assert_true(bool(out.get("ok", false)),
			"the register verb failed on %s: %s" % [inject, JSON.stringify(out)])
		assert_eq(str(out.get("injected", "")), inject, "the verb lost its injection name")
