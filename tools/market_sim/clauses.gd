extends RefCounted

## The clauses verb: a release clause, a sell-on, an agent fee, a bonus and the
## solidarity and training shares on one permanent move. No deal engine is
## loaded for the arithmetic; the money modules are the whole world.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- clauses \
##     --fee 40m --clause 35m --sell-on 10 --solidarity


static func run(options: Dictionary) -> Dictionary:
	var season := LeagueSeason.create("Clauses Sandbox", "generated", "fixture_days",
		int(options.get("seed", "7046")), ["PL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var from := str(options.get("from", "ENG-ARS1"))
	var to := str(options.get("to", "ENG-AVL1"))
	var player := str(options.get("player", ""))
	if player == "":
		player = str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
			[from]).get("id", ""))
	var fee := _money(str(options.get("fee", "40000000")))
	var clause := _money(str(options.get("clause", "35000000")))
	if str(options.get("clause", "")) != "":
		PLDatabase.execute(
			"UPDATE player_contract SET release_clause = ? WHERE player_id = ? AND status = 'active';",
			[clause, player])
	var sell_on := float(str(options.get("sell-on", "10"))) / 100.0
	if sell_on > 0.0:
		_seed_prior_sale(from, player, sell_on)
	if str(options.get("solidarity", "")) != "":
		_seed_youth_spells(from, player)
	var terms := {
		"fee": fee, "wage": int(MarketDealRecords.active_contract(player).get("wage", 5000)),
		"years": 4, "agent_fee": _money(str(options.get("agent", "2000000"))),
		"signing_bonus": _money(str(options.get("bonus", "1000000"))), "sell_on": sell_on,
	}
	var deal := {
		"id": "clauses-sandbox", "player_id": player, "from_club_id": from,
		"to_club_id": to, "fee": fee, "agent_fee": int(terms["agent_fee"]),
		"signing_bonus": int(terms["signing_bonus"]),
	}
	var extras := MarketAttribution.extras(deal)
	var clause_met := MarketAttribution.clause_met(player, fee)
	print("fee %d, clause %d, clause met %s" % [fee, clause, clause_met])
	print("sell-on %s, solidarity %d shares, training %s" % [
		JSON.stringify(extras.get("sell_on", {})),
		(extras.get("solidarity", []) as Array).size(),
		JSON.stringify(extras.get("training", {}))])
	var out := {
		"ok": clause_met and fee > 0,
		"fee": fee, "clause": clause, "clause_met": clause_met,
		"sell_on": extras.get("sell_on", {}), "solidarity": extras.get("solidarity", []),
		"training": extras.get("training", {}), "buyer_cost": MarketAttribution.buyer_cost(deal),
	}
	print("market_sim clauses: " + JSON.stringify(out))
	season.close()
	return out


static func _money(raw: String) -> int:
	var text := raw.strip_edges().to_lower()
	if text.ends_with("m"):
		return int(round(float(text.trim_suffix("m")) * 1_000_000.0))
	if text.ends_with("k"):
		return int(round(float(text.trim_suffix("k")) * 1_000.0))
	return int(text)


static func _seed_youth_spells(club_id: String, player_id: String) -> void:
	var birth := str(PLDatabase.row("SELECT date_of_birth FROM player WHERE id = ?;",
		[player_id]).get("date_of_birth", ""))
	if birth == "":
		return
	PLDatabase.execute("DELETE FROM player_history WHERE player_id = ?;", [player_id])
	PLDatabase.execute(
		"INSERT INTO player_history (player_id, season_index, club_id, competition_id, kind, "
		+ "from_date, to_date) VALUES (?, 0, ?, 'PL', 'spell', ?, ?);",
		[player_id, club_id, FixtureCalendar.add_years(birth, 13),
			FixtureCalendar.add_years(birth, 17)])


static func _seed_prior_sale(from_club_id: String, player_id: String, rate: float) -> void:
	PLDatabase.execute(
		"INSERT OR REPLACE INTO deal (id, kind, season_index, state, from_club_id, to_club_id, "
		+ "player_id, fee, sell_on, signed_on, opened_on) VALUES (?, 'permanent', 0, 'signed', ?, "
		+ "?, ?, 0, ?, '2025-07-01', '2025-07-01');",
		["clauses-prior:" + player_id, "ENG-LIV1", from_club_id, player_id, rate])
