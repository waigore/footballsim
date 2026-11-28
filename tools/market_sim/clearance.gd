extends RefCounted

## The clearance verb: a cross-association move pends, clears or fails with
## only the clearance module loaded.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- clearance \
##     --from ARS --to RMA --days 5 --inject clearance
##
## --inject  none | clearance (fail) | window (a window that closes first)


static func run(options: Dictionary) -> Dictionary:
	var season := LeagueSeason.create("Clearance Sandbox", "generated", "fixture_days",
		int(options.get("seed", "7047")), ["PL", "LL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var from := _club(options, "from", "ENG-ARS1")
	var to := _club(options, "to", "ESP-RMA1")
	var date := str(options.get("date", "2026-08-20"))
	var player := _player_at(from)
	var contract := MarketDealRecords.active_contract(player)
	var terms := {
		"fee": _money(str(options.get("fee", "5000000"))),
		"wage": int(contract.get("wage", 5000)), "years": 4, "agent_fee": 0,
		"signing_bonus": 0, "sell_on": 0.0,
	}
	var proposed := MarketDeals.propose(season, from, to, player, terms, date)
	var deal_id := str(proposed.get("deal", ""))
	var agreed := MarketDeals.agree(deal_id, date)
	var inject := str(options.get("inject", ""))
	var outcome := {}
	match inject:
		"clearance":
			outcome = MarketDeals.resolve_clearance(deal_id,
				str(agreed.get("clears_on", date)), {"clearance": "fail"})
		"window":
			outcome = MarketDeals.resolve_clearance(deal_id, "2026-09-10", {})
		_:
			outcome = MarketDeals.resolve_clearance(deal_id,
				str(agreed.get("clears_on", date)), {"clearance": "pass"})
	print("agreed: %s, clears on %s" % [str(agreed.get("state", "")),
		str(agreed.get("clears_on", ""))])
	print("outcome: %s (%s)" % [str(outcome.get("state", "")), str(outcome.get("reason", ""))])
	var out := {
		"ok": str(agreed.get("state", "")) == MarketDealRecords.CLEARANCE_PENDING,
		"deal": deal_id, "agreed": str(agreed.get("state", "")),
		"clears_on": str(agreed.get("clears_on", "")),
		"clearance_days": MarketDeals.clearance_days(deal_id),
		"outcome": str(outcome.get("state", "")), "reason": str(outcome.get("reason", "")),
	}
	print("market_sim clearance: " + JSON.stringify(out))
	season.close()
	return out


static func _club(options: Dictionary, key: String, fallback: String) -> String:
	var raw := str(options.get(key, fallback))
	if PLDatabase.row("SELECT id FROM club WHERE id = ?;", [raw]).is_empty():
		var other := str(PLDatabase.row(
			"SELECT id FROM club WHERE id LIKE ? ORDER BY id LIMIT 1;", ["%" + raw + "%"]).get(
			"id", ""))
		if other != "":
			return other
		return fallback
	return raw


static func _player_at(club_id: String) -> String:
	return str(PLDatabase.row(
		"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
		[club_id]).get("id", ""))


static func _money(raw: String) -> int:
	var text := raw.strip_edges().to_lower()
	if text.ends_with("m"):
		return int(round(float(text.trim_suffix("m")) * 1_000_000.0))
	if text.ends_with("k"):
		return int(round(float(text.trim_suffix("k")) * 1_000.0))
	return int(text)
