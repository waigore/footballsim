extends RefCounted

## The loan verb: propose, split the wage, fire a trigger and return one loan
## with no AI, no news feed and no UI loaded.
##
##   godot --headless --path . --script res://tools/market_sim.gd -- loan \
##     --trigger appearances_n=10 --clubs 20
##
## --trigger  none | appearances_n=N | club_promoted | league_position=N | season_end


static func run(options: Dictionary) -> Dictionary:
	var season := LeagueSeason.create("Loan Sandbox", "generated", "fixture_days",
		int(options.get("seed", "7045")), ["PL"], false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var parent := str(options.get("from", "ENG-ARS1"))
	var loanee := str(options.get("to", "ENG-AVL1"))
	var date := str(options.get("date", "2026-08-20"))
	var player := str(options.get("player", ""))
	if player == "":
		player = str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC LIMIT 1;",
			[parent]).get("id", ""))
	var wage := int(MarketDealRecords.active_contract(player).get("wage", 5000))
	var trigger := _parse_trigger(str(options.get("trigger", "none")))
	var terms := {
		"wage": wage, "wage_loanee": int(options.get("wage_loanee", str(wage / 2))),
		"start_date": date, "end_date": str(options.get("end_date", "2027-05-31")),
		"fee": int(options.get("fee", "0")),
		"option_kind": str(options.get("option", "obligation" if trigger["kind"] != "" else "none")),
		"buy_fee": int(options.get("buy", "3000000")),
		"trigger_kind": str(trigger["kind"]), "trigger_value": str(trigger["value"]),
	}
	var proposed := MarketLoans.propose(season.save, parent, loanee, player, terms, date)
	var loan_id := str(proposed.get("loan", ""))
	print("proposed %s: %s -> %s" % [loan_id, parent, loanee])
	var sealed := MarketLoans.seal(loan_id, date)
	print("sealed: %s; split %d / %d" % [str(sealed.get("state", "")),
		int(sealed.get("wage_parent", 0)), int(sealed.get("wage_loanee", 0))])
	if str(trigger["kind"]) == "appearances_n":
		PLDatabase.execute(
			"INSERT OR REPLACE INTO league_player_stat (player_id, competition_id, club_id, "
			+ "season_index, apps, goals) VALUES (?, 'PL', ?, 0, ?, 1);",
			[player, loanee, int(trigger["value"])])
	if str(trigger["kind"]) == "season_end":
		PLDatabase.execute("UPDATE league_fixture SET status = 'played' WHERE status <> 'played';")
	var fired := MarketLoans.fire_obligations(season.save, str(options.get("trigger_date", "2026-10-01")))
	print("obligations fired: %d" % fired)
	var returned := {}
	if fired == 0 and str(options.get("return", "1")) != "0":
		returned = MarketLoans.return_loan(loan_id, str(options.get("return_date", "2027-05-31")))
		print("returned: %s" % str(returned.get("state", "")))
	var loan := MarketLoanRecords.load(loan_id)
	var split_ok := int(loan.get("wage_parent", 0)) + int(loan.get("wage_loanee", 0)) == wage
	var out := {
		"ok": split_ok and (fired > 0 or str(returned.get("state", "")) != "" or str(
			options.get("return", "1")) == "0"),
		"loan": loan_id, "state": str(loan.get("status", "")),
		"wage": wage, "wage_parent": int(loan.get("wage_parent", 0)),
		"wage_loanee": int(loan.get("wage_loanee", 0)), "split_ok": split_ok,
		"fired": fired, "returned": str(returned.get("state", "")),
	}
	print("market_sim loan: " + JSON.stringify(out))
	season.close()
	return out


static func _parse_trigger(raw: String) -> Dictionary:
	if raw == "" or raw == "none":
		return {"kind": "", "value": ""}
	var parts := raw.split("=", true, 1)
	return {"kind": str(parts[0]), "value": str(parts[1]) if parts.size() > 1 else ""}
