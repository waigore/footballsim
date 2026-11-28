extends RefCounted

## The deal verb: one permanent move through the engine on the fixed clock.
## No AI, no news feed and no UI is loaded; the money, contract, registration
## and history modules are the whole world.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- deal \
##     --from ENG-ARS1 --to ESP-ALA1 --fee 5000000 --inject clearance
##
## --inject  none | list | clearance | fault | registration


static func run(options: Dictionary) -> Dictionary:
	var season := LeagueSeason.create("Deal Sandbox", "generated", "fixture_days",
		int(options.get("seed", "7043")), ["PL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var from := str(options.get("from", "ENG-ARS1"))
	var to := str(options.get("to", "ENG-CHE1"))
	var date := str(options.get("date", "2026-08-20"))
	var player := str(options.get("player", ""))
	if player == "":
		player = str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
			[from]).get("id", ""))
	var terms := terms_for(player, options)
	var opened := MarketDeals.propose(season, from, to, player, terms, date)
	var deal_id := str(opened.get("deal", ""))
	print("proposed %s: %s -> %s for %s on %s" % [deal_id, from, to,
		MarketCurrency.format(int(terms["fee"])), date])
	var inject := str(options.get("inject", ""))
	var mode := {}
	if inject == "list":
		mode["list"] = "refuse"
	var agreed := MarketDeals.agree(deal_id, date, mode)
	print("agreed: %s (%s)" % [str(agreed.get("state", "")), str(agreed.get("reason", ""))])
	var done := {}
	match inject:
		"clearance":
			done = MarketDeals.resolve_clearance(deal_id, str(agreed.get("clears_on", date)),
				{"clearance": "fail"})
		"fault":
			done = MarketDeals.sign(deal_id, date, {"fault": "contract"})
		"registration":
			done = MarketDeals.sign(deal_id, date, {"registration": "refuse"})
		_:
			done = MarketDeals.sign(deal_id, date, mode)
	var buyer := MarketFinance.club(to)
	var registration := MarketDealRecords.registration(player, str(buyer.get("competition_id", "")))
	print("signed: %s; cash %s; registration %s" % [str(done.get("state", "")),
		MarketCurrency.format(int(done.get("cash", 0))), str(registration.get("state", "none"))])
	print("market_sim deal: " + JSON.stringify(done))
	season.close()
	return done


static func terms_for(player_id: String, options: Dictionary) -> Dictionary:
	var contract := MarketDealRecords.active_contract(player_id)
	var wage := int(options.get("wage", str(contract.get("wage", 5000))))
	var fee := int(options.get("fee", "5000000"))
	return {
		"fee": fee, "wage": wage, "years": int(options.get("years", "4")),
		"agent_fee": int(options.get("agent", str(maxi(int(round(fee * 0.05)), 0)))),
		"signing_bonus": int(options.get("bonus", "0")),
		"sell_on": 0.0,
	}
