extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_squad_list_448")
var CACHE_DIR := TestScratch.dir("cache_squad_list_448")
const SEED := 4480
const DATE := "2026-08-20"

var opened: Array = []


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
	_clean()
	LeagueSave.dir = LeagueSave.DEFAULT_DIR
	PLDatabase.cache_dir = PLDatabase.CACHE_DIR
	PLDatabase.reset()
	PLRepository.shared().invalidate()


func _clean() -> void:
	TestScratch.clear(SAVE_DIR)
	TestScratch.clear(CACHE_DIR)


func _europe(name: String) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", SEED, ["PL"], false, [],
		true)
	assert_not_null(season, "%s was not created: %s" % [name, LeagueSave.last_error])
	opened.append(season)
	return season


func _count(sql: String, bindings: Array = []) -> int:
	return int(PLDatabase.row(sql, bindings).get("n", 0))


func _real_entrant(competition_id: String) -> String:
	var rows := PLDatabase.rows(
		"SELECT cm.member_id FROM competition_member cm JOIN club c ON c.id = cm.member_id "
		+ "JOIN player p ON p.club_id = c.id "
		+ "WHERE cm.competition_id = ? AND cm.member_kind = 'club' AND c.stub = 0 "
		+ "GROUP BY cm.member_id ORDER BY COUNT(p.id) DESC, cm.member_id;", [competition_id])
	assert_false(rows.is_empty(), "%s has no real entrant" % competition_id)
	return str(rows[0]["member_id"])


func _eng_entrant() -> String:
	var rows := PLDatabase.rows(
		"SELECT cm.member_id FROM competition_member cm JOIN club c ON c.id = cm.member_id "
		+ "JOIN player p ON p.club_id = c.id "
		+ "WHERE cm.competition_id = 'UCL' AND cm.member_kind = 'club' AND c.stub = 0 "
		+ "AND c.competition_id = 'PL' GROUP BY cm.member_id "
		+ "ORDER BY COUNT(p.id) DESC, cm.member_id;")
	assert_false(rows.is_empty(), "no English club is in the Champions League")
	return str(rows[0]["member_id"])


func _seller() -> String:
	var rows := PLDatabase.rows(
		"SELECT c.id FROM club c WHERE c.competition_id = 'PL' AND c.stub = 0 "
		+ "AND NOT EXISTS (SELECT 1 FROM competition_member cm WHERE cm.member_kind = 'club' "
		+ "AND cm.member_id = c.id AND cm.competition_id IN ('UCL', 'UEL', 'UECL')) "
		+ "ORDER BY c.id;")
	assert_false(rows.is_empty(), "the league has no club outside Europe")
	return str(rows[0]["id"])


func _terms(player_id: String, overrides: Dictionary = {}) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player_id)
	var terms := {
		"fee": 5_000_000, "wage": int(contract.get("wage", 5000)), "years": 4,
		"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0,
	}
	for key in overrides:
		terms[key] = overrides[key]
	return terms


func _propose(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary, date: String = DATE) -> String:
	var out := MarketDeals.propose(season.save, from, to, player, terms, date)
	assert_true(str(out.get("deal", "")) != "", "the deal was not proposed")
	return str(out.get("deal", ""))


func _extra_adult(seller: String) -> String:
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id = ? AND age >= 21 ORDER BY ovr, id;", [seller]):
		return str(row["id"])
	var spare := PLDatabase.rows(
		"SELECT p.id FROM player p JOIN club c ON c.id = p.club_id "
		+ "WHERE c.competition_id = 'PL' AND c.stub = 0 AND p.club_id <> ? AND p.age >= 21 "
		+ "AND NOT EXISTS (SELECT 1 FROM competition_member cm WHERE cm.member_kind = 'club' "
		+ "AND cm.member_id = c.id AND cm.competition_id IN ('UCL', 'UEL', 'UECL')) "
		+ "ORDER BY p.ovr, p.id LIMIT 1;", [seller])
	if spare.is_empty():
		return ""
	return str((spare[0] as Dictionary)["id"])


func _fill_list(club: String, competition_id: String, seller: String) -> void:
	var squad := PLDatabase.rows(
		"SELECT id FROM player WHERE club_id = ? AND age >= 21 ORDER BY id;", [club])
	for row in squad:
		SquadList.register(club, competition_id, str(row["id"]), SquadList.REGISTERED)
	var used := SquadList.slots_used(club, competition_id)
	while used < SquadList.slots():
		var rider := _extra_adult(seller)
		assert_true(rider != "", "the league ran out of adults")
		PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [club, rider])
		SquadList.register(club, competition_id, rider, SquadList.REGISTERED)
		used += 1


func test_the_seed_registers_every_uefa_entrant() -> void:
	var season := _europe("List Seed")
	var members := _count(
		"SELECT COUNT(DISTINCT member_id) AS n FROM competition_member "
		+ "WHERE member_kind = 'club' AND competition_id IN ('UCL', 'UEL', 'UECL');")
	assert_gt(members, 0, "the seed names no UEFA entrant")
	var registered := _count(
		"SELECT COUNT(DISTINCT club_id) AS n FROM player_registration "
		+ "WHERE competition_id IN ('UCL', 'UEL', 'UECL');")
	assert_eq(registered, members, "not every UEFA entrant holds a list")
	var stub := PLDatabase.row(
		"SELECT c.id FROM competition_member cm JOIN club c ON c.id = cm.member_id "
		+ "WHERE cm.competition_id IN ('UCL', 'UEL', 'UECL') AND c.stub = 1 "
		+ "ORDER BY c.id LIMIT 1;")
	assert_false(stub.is_empty(), "the seed ships no stub entrant")
	var eleven := _count(
		"SELECT COUNT(*) AS n FROM player_registration WHERE club_id = ?;",
		[str(stub["id"])])
	assert_eq(eleven, 11, "a stub entrant did not register its playable eleven")
	season.close()


func test_a_real_club_reads_a_twenty_five_slot_list() -> void:
	var season := _europe("List Reading")
	var club := _real_entrant("UCL")
	var reading := SquadList.reading(club, "UCL")
	assert_false(reading.is_empty(), "the entrant publishes no list")
	assert_eq(int(reading["slots"]), 25, "the list is not twenty-five slots")
	assert_eq(int(reading["trained_min"]), 4, "the list lost its trained places")
	assert_eq(int(reading["slots_used"]), SquadList.slots_used(club, "UCL"),
		"the reading disagrees with the list")
	assert_true((reading["players"] as Array).size() > 0, "the list names nobody")
	assert_eq(str(reading["competition"]), "UCL", "the reading names the wrong competition")
	season.close()


func test_an_under_21_player_takes_no_slot() -> void:
	var season := _europe("List U21")
	var club := _real_entrant("UCL")
	var youth := ""
	for row in PLDatabase.rows(
			"SELECT id FROM player WHERE club_id = ? AND age > 0 AND age < 21 ORDER BY id;",
			[club]):
		youth = str(row["id"])
		break
	assert_true(youth != "", "the entrant has no under-21 player")
	assert_true(SquadList.exempt(youth), "an under-21 player was counted")
	var before := SquadList.slots_used(club, "UCL")
	SquadList.register(club, "UCL", youth, SquadList.REGISTERED)
	assert_eq(SquadList.slots_used(club, "UCL"), before, "an exempt player consumed a slot")
	var reading := SquadList.reading(club, "UCL")
	var exempt := 0
	for player in reading["players"]:
		if bool(player["exempt"]):
			exempt += 1
	assert_gte(exempt, 1, "the reading does not mark the under-21 place")
	season.close()


func test_the_twenty_sixth_signing_refuses_with_list_full() -> void:
	var season := _europe("List Full")
	var club := _eng_entrant()
	var seller := _seller()
	_fill_list(club, "UCL", seller)
	assert_eq(SquadList.slots_used(club, "UCL"), SquadList.slots(),
		"the list did not fill to its cap")
	var rider := _extra_adult(seller)
	assert_true(rider != "", "the seller has no adult left")
	var verdict := SquadList.verdict(club, "UCL", rider)
	assert_false(bool(verdict.get("ok", true)), "a full list accepted a signing")
	assert_eq(str(verdict.get("code", "")), SquadList.FULL, "the refusal has no code")
	var agreed := MarketDeals.agree(_propose(season, seller, club, rider,
		_terms(rider, {"fee": 1_000})), DATE)
	assert_eq(str(agreed.get("reason", "")), MarketDealRules.LIST,
		"the engine signed past a full list")
	assert_eq(str(agreed.get("state", "")), MarketDealRecords.FAILED, "the refused deal stayed live")
	season.close()


func test_force_never_skips_the_list() -> void:
	var season := _europe("List Force")
	var club := _eng_entrant()
	var seller := _seller()
	_fill_list(club, "UCL", seller)
	var rider := _extra_adult(seller)
	assert_true(rider != "", "the seller has no adult left")
	var forced := MarketDeals.force(_propose(season, seller, club, rider,
		_terms(rider, {"fee": 1_000})), DATE)
	assert_eq(str(forced.get("state", "")), MarketDealRecords.SIGNED,
		"a forced deal was voided by the list: %s" % str(forced.get("reason", "")))
	assert_eq(str(PLDatabase.row("SELECT club_id FROM player WHERE id = ?;", [rider]).get(
		"club_id", "")), club, "a forced signing did not move")
	assert_eq(SquadList.state_of(rider, "UCL"), SquadList.INELIGIBLE,
		"a forced signing past the list reads selectable")
	var xi: Array = []
	for picked in StrongestXI.pick(PLRepository.shared().team(club), "UCL"):
		xi.append(str((picked as Dictionary).get("id", "")))
	assert_false(xi.has(rider), "the XI picked a UEFA-ineligible player")
	season.close()


func test_the_club_page_shows_the_uefa_list() -> void:
	var season := _europe("List Page")
	var club := _real_entrant("UCL")
	var page := WikiTeam.page(club)
	var heading := "%s LIST  ·  %d / %d" % [LeagueUefa.name_of("UCL").to_upper(),
		SquadList.slots_used(club, "UCL"), SquadList.slots()]
	var found := false
	var rows := 0
	for block in page.get("blocks", []):
		if str(block.get("k", "")) == "section" and str(block.get("text", "")) == heading:
			found = true
			continue
		if found and str(block.get("k", "")) == "table":
			rows = (block.get("rows", []) as Array).size()
			break
	assert_true(found, "the club page has no %s section" % heading)
	assert_gte(rows, 11, "the UEFA list block printed too few rows")
	season.close()


func test_a_domestic_club_without_europe_shows_no_uefa_list() -> void:
	var season := _europe("List Domestic")
	var club := _seller()
	assert_true(SquadList.entries(club).is_empty(), "the fixture club is in Europe")
	var page := WikiTeam.page(club)
	for block in page.get("blocks", []):
		if str(block.get("k", "")) == "section":
			assert_false(" LIST  ·  " in str(block.get("text", "")),
				"a club outside Europe printed a UEFA list")
	season.close()


func test_a_refused_registration_also_refuses_the_uefa_row() -> void:
	var season := _europe("List Refusal")
	var club := _eng_entrant()
	var seller := _seller()
	var rider := _extra_adult(seller)
	assert_true(rider != "", "the seller has no adult")
	var deal := _propose(season, seller, club, rider, _terms(rider, {"fee": 1_000}))
	assert_eq(str(MarketDeals.agree(deal, DATE).get("state", "")), MarketDealRecords.AGREED,
		"the deal did not agree")
	var done := MarketDeals.seal(deal, DATE, {"registration": "refuse"})
	assert_eq(str(done.get("state", "")), MarketDealRecords.SIGNED,
		"a refused registration voided the deal")
	assert_eq(SquadList.state_of(rider, "UCL"), SquadList.INELIGIBLE,
		"the UEFA row escaped the refused registration")
	assert_eq(str(PLDatabase.row(
		"SELECT state FROM player_registration WHERE player_id = ? AND competition_id = 'PL';",
		[rider]).get("state", "")), SquadList.INELIGIBLE, "the domestic row was overwritten")
	season.close()


func test_the_engine_refuses_an_empty_list_call() -> void:
	assert_true(SquadList.entries("").is_empty(), "an empty club named a list")
	assert_true(SquadList.reading("", "UCL").is_empty(), "an empty club read a list")
	assert_eq(SquadList.state_of("", "UCL"), "", "an empty player held a state")
	assert_false(SquadList.register("", "UCL", "", SquadList.REGISTERED), "an empty row wrote")
	assert_true(bool(SquadList.verdict("", "UCL", "").get("ok", false)), "an empty verdict refused")
	assert_true(bool(SquadList.verdict("ENG-ARS1", "PL", "x").get("ok", false)),
		"a domestic competition was listed")
	assert_true(SquadList.ineligible_ids("", "UCL").is_empty(), "an empty club refused a player")
