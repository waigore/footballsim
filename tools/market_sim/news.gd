extends RefCounted

## The news verb: scripted deals build a rumour and a done-deal feed. No AI,
## no market tick and no UI is loaded; the deal engine and its state rows only.

static func run(options: Dictionary) -> Dictionary:
	var wanted := maxi(int(options.get("deals", "20")), 1)
	var inject := str(options.get("inject", ""))
	var season := LeagueSeason.create("News Sandbox", "generated", "fixture_days",
		int(options.get("seed", "7061")), ["PL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var date := "2026-08-20"
	var closed := "2026-12-20"
	var clubs: Array = []
	for row in PLDatabase.rows("SELECT id FROM club WHERE competition_id = 'PL' ORDER BY id;"):
		clubs.append(str(row["id"]))
	var made := 0
	var failures: Array = []
	for i in range(wanted):
		var from := str(clubs[i % clubs.size()])
		var to := str(clubs[(i + 1) % clubs.size()])
		var player := str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
			[from]).get("id", ""))
		if player == "":
			continue
		var contract := MarketDealRecords.active_contract(player)
		var fee := 5_000_000 + i * 250_000
		var terms := {"fee": fee, "wage": int(contract.get("wage", 5000)), "years": 3,
			"agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}
		var deal := MarketDeals.propose(season, from, to, player, terms, date)
		var deal_id := str(deal.get("deal", ""))
		if deal_id == "":
			failures.append({"deal": "", "reason": "propose"})
			continue
		MarketDeals.negotiate(deal_id, date)
		if inject == "blocked" and i == 0:
			MarketDeals.block(deal_id, date, "scripted veto")
			made += 1
			continue
		if i % 5 == 3:
			MarketDeals.force(deal_id, date)
		elif i % 7 == 5:
			var other := str(clubs[(i + 2) % clubs.size()])
			var blocked := MarketDeals.propose(season, from, other, player, terms, date)
			var blocked_id := str(blocked.get("deal", ""))
			if blocked_id != "":
				MarketDeals.block(blocked_id, date, "scripted veto")
		else:
			MarketDeals.agree(deal_id, date)
			MarketDeals.seal(deal_id, date)
		made += 1
	var failed_from := str(clubs[wanted % clubs.size()])
	var failed_player := str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
		[failed_from]).get("id", ""))
	if failed_player != "":
		var failed_terms := {"fee": 6_000_000,
			"wage": int(MarketDealRecords.active_contract(failed_player).get("wage", 5000)),
			"years": 2, "agent_fee": 0, "signing_bonus": 0, "sell_on": 0.0}
		var doomed := MarketDeals.propose(season, failed_from, str(clubs[0]), failed_player,
			failed_terms, closed)
		MarketDeals.agree(str(doomed.get("deal", "")), closed)
	var kinds := {}
	for row in PLDatabase.rows("SELECT kind, COUNT(*) AS n FROM market_news GROUP BY kind;"):
		kinds[str(row["kind"])] = int(row["n"])
	var feed := MarketNews.feed(-1, 20)
	print("news: %d deals, feed %d, kinds %s" % [made, feed.size(), JSON.stringify(kinds)])
	season.close()
	return {"ok": feed.size() > 0 and not kinds.is_empty(), "deals": made, "feed": feed.size(),
		"kinds": kinds, "failures": failures, "sample": feed.slice(0, 3)}
