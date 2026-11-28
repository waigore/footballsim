class_name LeagueMarketView
extends RefCounted


static func date(screen) -> String:
	if screen == null or screen.season == null or screen.season.save == null:
		return ""
	return screen.season.save.current_date()


static func season_index(screen) -> int:
	if screen == null or screen.season == null or screen.season.save == null:
		return 0
	return screen.season.save.season_index()


static func hub(screen) -> Dictionary:
	var day := date(screen)
	var index := season_index(screen)
	var windows := MarketWindows.board(day)
	var open_one := false
	for window in windows:
		if bool((window as Dictionary).get("open", false)):
			open_one = true
	return {
		"date": day, "season_index": index, "windows": windows, "any_open": open_one,
		"news": MarketNews.feed(index, 8), "news_count": MarketNews.count(index),
		"free_agents": free_agents(8), "movers": movers(index, 6),
		"touch": bool(screen.touch), "deal": "",
	}


static func news(screen) -> Dictionary:
	var index := season_index(screen)
	return {"date": date(screen), "feed": MarketNews.feed(index, 100),
		"count": MarketNews.count(index), "touch": bool(screen.touch)}


static func deal(screen) -> Dictionary:
	var deal_id := str(screen.deal_id)
	var deal := MarketDealRecords.load(deal_id)
	if deal.is_empty():
		return {"empty": true, "deal_id": deal_id, "touch": bool(screen.touch),
			"date": date(screen)}
	var day := date(screen)
	var buyer := str(deal.get("to_club_id", ""))
	var buyer_club := MarketDealRules.club_row(buyer)
	var window := MarketWindows.state(day, MarketWindows.country_of_club(buyer_club)) \
		if not buyer_club.is_empty() else {"open": true, "opens_on": "", "closes_on": ""}
	var free := MarketDealRules.is_free_agent(deal)
	var checks: Array = []
	for name in MarketDealRules.ORDER:
		if name == "window" and free:
			checks.append({"name": "window", "ok": true, "code": "ok", "detail": "free agent"})
			continue
		var verdict := MarketDealRules.check(str(name), deal, day)
		checks.append({"name": str(name), "ok": bool(verdict.get("ok", false)),
			"code": str(verdict.get("code", "")), "detail": str(verdict.get("detail", ""))})
	var terms: Array = [
		["PLAYER", player_name(str(deal.get("player_id", "")))],
		["FROM", club_name(str(deal.get("from_club_id", "")))],
		["TO", club_name(buyer)],
		["FEE", MarketCurrency.format(int(deal.get("fee", 0)))],
		["WAGE", MarketWages.weekly(int(deal.get("wage", 0)))],
		["YEARS", str(int(deal.get("years", 1)))],
		["AGENT", MarketCurrency.format(int(deal.get("agent_fee", 0)))],
		["BONUS", MarketCurrency.format(int(deal.get("signing_bonus", 0)))],
		["SELL-ON", "%d%%" % int(round(float(deal.get("sell_on", 0.0)) * 100.0))],
	]
	return {
		"empty": false, "deal_id": deal_id, "deal": deal, "date": day,
		"state": str(deal.get("state", "")), "god": str(deal.get("god", "")),
		"reason": str(deal.get("reason", "")), "terms": terms, "checks": checks,
		"timeline": MarketDealRecords.events(deal_id), "window": window,
		"free_agent": free, "touch": bool(screen.touch),
		"can_act": str(deal.get("state", "")) != MarketDealRecords.SIGNED
			and (bool(window.get("open", false)) or free),
	}


static func free_agents(limit: int) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT p.id, p.name, p.pos, p.ovr, p.club_id, "
			+ "(SELECT c.club_id FROM player_contract c WHERE c.player_id = p.id "
			+ "ORDER BY c.end_date DESC LIMIT 1) AS last_club FROM player p "
			+ "WHERE NOT EXISTS (SELECT 1 FROM player_contract c "
			+ "WHERE c.player_id = p.id AND c.status = 'active') "
			+ "ORDER BY p.ovr DESC, p.id LIMIT ?;", [maxi(limit, 1)]):
		out.append({"id": str(row["id"]), "name": str(row.get("name", "")),
			"pos": str(row.get("pos", "")), "ovr": int(row.get("ovr", 0)),
			"last_club": club_name(str(row.get("last_club", "")))})
	return out


static func movers(index: int, limit: int) -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT * FROM deal WHERE season_index = ? AND state = 'signed' "
			+ "ORDER BY fee DESC, id LIMIT ?;", [index, maxi(limit, 1)]):
		var item: Dictionary = row
		item["player_name"] = player_name(str(row.get("player_id", "")))
		item["from_name"] = club_name(str(row.get("from_club_id", "")))
		item["to_name"] = club_name(str(row.get("to_club_id", "")))
		out.append(item)
	return out


static func player_name(player_id: String) -> String:
	if player_id == "":
		return "A PLAYER"
	return str(PLDatabase.row("SELECT name FROM player WHERE id = ?;", [player_id]).get(
		"name", player_id))


static func club_name(club_id: String) -> String:
	if club_id == "":
		return "FREE AGENT"
	return str(PLDatabase.row("SELECT name FROM club WHERE id = ?;", [club_id]).get(
		"name", club_id))
