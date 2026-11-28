extends GdToolsTest


var SAVE_DIR := TestScratch.dir("saves_news_452")
var CACHE_DIR := TestScratch.dir("cache_news_452")
const SEED := 7452
const DATE := "2026-08-20"
const CLOSED := "2026-12-20"

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


func _fresh(name: String, seed_value: int = SEED) -> LeagueSeason:
	var season := LeagueSeason.create(name, "generated", "fixture_days", seed_value, ["PL"], false)
	assert_not_null(season, "%s was not created" % name)
	opened.append(season)
	return season


func _club(index: int = 0, lowest: bool = false) -> String:
	var order := "DESC" if not lowest else "ASC"
	return str(PLDatabase.row(
		"SELECT club_id FROM club_finance ORDER BY reputation %s, club_id LIMIT 1 OFFSET ?;"
		% order, [index]).get("club_id", ""))


func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
		[club_id]).get("id", ""))


func _terms(player_id: String, fee: int = 5_000_000) -> Dictionary:
	return {"fee": fee,
		"wage": int(MarketDealRecords.active_contract(player_id).get("wage", 5000)),
		"years": 3, "agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}


func _propose(season: LeagueSeason, from: String, to: String, player: String,
		terms: Dictionary, date: String = DATE) -> String:
	return str(MarketDeals.propose(season, from, to, player, terms, date).get("deal", ""))


func _count(kind: String) -> int:
	return int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM market_news WHERE kind = ?;", [kind]).get("n", 0))


func test_a_negotiating_deal_at_five_million_writes_one_rumour() -> void:
	var season := _fresh("News Rumour")
	var from := _club(0, true)
	var to := _club(1, true)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player))
	MarketDeals.negotiate(deal, DATE)
	assert_eq(_count(MarketNews.RUMOUR), 1, "the deal wrote no rumour")
	var item: Dictionary = MarketNews.feed(-1, 10)[0]
	assert_eq(str(item.get("kind", "")), MarketNews.RUMOUR, "the feed lost the rumour")
	assert_eq(str(item.get("deal_id", "")), deal, "the rumour names another deal")


func test_a_quiet_low_fee_deal_writes_no_rumour() -> void:
	var season := _fresh("News Quiet")
	var from := _club(0, true)
	var to := _club(1, true)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player, 250_000))
	MarketDeals.negotiate(deal, DATE)
	assert_eq(_count(MarketNews.RUMOUR), 0, "a quiet deal raised a rumour")


func test_a_top_six_club_raises_a_rumour_at_any_fee() -> void:
	var season := _fresh("News Top Six")
	var from := _club(0)
	var to := _club(1)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player, 250_000))
	MarketDeals.negotiate(deal, DATE)
	assert_eq(_count(MarketNews.RUMOUR), 1, "a top-six deal stayed quiet")


func test_signed_blocked_failed_and_forced_each_write_one_item() -> void:
	var season := _fresh("News Kinds")
	var from := _club(0, true)
	var to := _club(1, true)
	var player := _player_at(from)
	var signed := _propose(season, from, to, player, _terms(player, 100_000))
	MarketDeals.agree(signed, DATE)
	MarketDeals.seal(signed, DATE)
	assert_eq(_count(MarketNews.SIGNED), 1, "a signing wrote no news")

	var blocked_from := _club(2, true)
	var blocked := _propose(season, blocked_from, _club(3, true), _player_at(blocked_from),
		_terms(_player_at(blocked_from), 100_000))
	MarketDeals.block(blocked, DATE)
	assert_eq(_count(MarketNews.BLOCKED), 1, "a block wrote no news")

	var failed_from := _club(4, true)
	var failed := _propose(season, failed_from, _club(5, true), _player_at(failed_from),
		_terms(_player_at(failed_from), 100_000), CLOSED)
	MarketDeals.agree(failed, CLOSED)
	assert_eq(_count(MarketNews.FAILED), 1, "a failed deal wrote no news")

	var forced_from := _club(6, true)
	var forced := _propose(season, forced_from, _club(7, true), _player_at(forced_from),
		_terms(_player_at(forced_from), 100_000))
	MarketDeals.force(forced, DATE)
	assert_eq(_count(MarketNews.FORCED), 1, "a forced deal wrote no forced news")
	assert_eq(_count(MarketNews.SIGNED), 1, "a forced deal was also read as a plain signing")


func test_the_same_deal_and_kind_never_appears_twice() -> void:
	var season := _fresh("News Dedupe")
	var deal := {"id": "dup:1", "season_index": 0, "player_id": "p", "to_club_id": "c"}
	assert_true(MarketNews.create(MarketNews.SIGNED, deal, DATE), "the first item was refused")
	MarketNews.create(MarketNews.SIGNED, deal, DATE)
	assert_eq(_count(MarketNews.SIGNED), 1, "the feed duplicated a deal and kind")
	MarketNews.create(MarketNews.FORCED, deal, DATE)
	assert_eq(_count(MarketNews.FORCED), 1, "a different kind was refused")


func test_a_season_never_exceeds_the_cap_and_the_oldest_are_pruned() -> void:
	var season := _fresh("News Cap")
	for i in range(520):
		MarketNews.create(MarketNews.SIGNED, {"id": "cap:%d" % i, "season_index": 0,
			"player_id": "p", "to_club_id": "c"}, DATE)
	assert_eq(MarketNews.count(0), MarketNews.CAP, "the feed passed its cap")
	assert_true(PLDatabase.row("SELECT id FROM market_news WHERE dedupe_key = ?;",
		["cap:0|signed"]).is_empty(), "the oldest item survived the prune")
	assert_false(PLDatabase.row("SELECT id FROM market_news WHERE dedupe_key = ?;",
		["cap:519|signed"]).is_empty(), "the newest item was pruned")


func test_every_item_links_to_its_deal_player_and_clubs() -> void:
	var season := _fresh("News Links")
	var from := _club(0, true)
	var to := _club(1, true)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player, 100_000))
	MarketDeals.agree(deal, DATE)
	MarketDeals.seal(deal, DATE)
	var item: Dictionary = MarketNews.feed(-1, 1)[0]
	assert_false(MarketDealRecords.load(str(item["deal_id"])).is_empty(), "the deal link is dead")
	assert_false(PLDatabase.row("SELECT id FROM player WHERE id = ?;",
		[str(item["player_id"])]).is_empty(), "the player link is dead")
	assert_true(str(item.get("to_name", "")) != "", "the item names no buying club")
	assert_true(str(item.get("headline", "")) != "", "the item has no headline")


func test_the_roundup_digest_never_blocks_continue() -> void:
	var season := _fresh("News Digest")
	var from := _club(0, true)
	var to := _club(1, true)
	var player := _player_at(from)
	var deal := _propose(season, from, to, player, _terms(player, 100_000))
	MarketDeals.agree(deal, DATE)
	MarketDeals.seal(deal, DATE)
	var digest := MarketNews.digest(DATE)
	assert_false(digest.is_empty(), "the day's deals left no digest")
	var fixture := {"id": "f1", "kickoff": DATE, "competition_id": "PL", "matchday": 1,
		"home_club_id": from, "away_club_id": to, "home_goals": 1, "away_goals": 0,
		"status": "played", "home_name": "Home", "away_name": "Away"}
	var items: Array = LeagueReportSheet.new().layout(Vector2(1600, 900), {
		"roundup": [{"fixture": fixture, "events": [], "score": [1, 0], "played": true}],
		"market_news": digest, "day": DATE,
	})
	var has_continue := false
	var has_news := false
	for item in items:
		if str(item["id"]) == "continue":
			has_continue = true
		if str(item["kind"]) == "news":
			has_news = true
	assert_true(has_continue, "the digest cost the roundup its CONTINUE")
	assert_true(has_news, "the digest drew no news row")


func test_the_isolated_news_run_builds_every_kind_and_repeats() -> void:
	var script: Script = load("res://tools/market_sim/news.gd")
	var first: Dictionary = script.run({"deals": "20", "inject": "blocked", "seed": "7061"})
	assert_true(bool(first.get("ok", false)), "the isolated news run refused")
	var kinds: Dictionary = first.get("kinds", {})
	assert_true(kinds.has(MarketNews.BLOCKED), "the scripted veto wrote no blocked news")
	assert_true(kinds.has(MarketNews.SIGNED), "the scripted run wrote no signing")
	assert_true(kinds.has(MarketNews.RUMOUR), "the scripted run wrote no rumour")
	assert_true(kinds.has(MarketNews.FAILED), "the scripted run wrote no failure")
	var second: Dictionary = script.run({"deals": "20", "inject": "blocked", "seed": "7061"})
	assert_true(bool(second.get("ok", false)), "the repeated news run refused")
	assert_eq(JSON.stringify(second.get("kinds", {})), JSON.stringify(kinds),
		"a repeated run changed its feed")
