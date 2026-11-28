extends RefCounted

## The deal verb: propose, agree and sign one move through the L5 engine.
## A window is open, registration allow-lists, clearance is instant and the
## news feed is null. --inject forces a failure path.


static func run(options: Dictionary) -> Dictionary:
	var seed_value := int(options.get("seed", "7504"))
	var clubs := maxi(int(options.get("clubs", "20")), 2)
	var competitions := ["PL"]
	if clubs > 20:
		competitions.append("CH")
	var season := LeagueSeason.create("Deal Sandbox", "generated", "fixture_days", seed_value,
		competitions, false)
	if season == null:
		return {"ok": false, "reason": "the save could not be created",
			"detail": LeagueSave.last_error}
	var from_row := _club(str(options.get("from", "ENG-ARS1")))
	var to_row := _club(str(options.get("to", "ENG-AVL1")))
	if from_row.is_empty() or to_row.is_empty():
		season.close()
		return {"ok": false, "reason": "the clubs could not be resolved"}
	var date := str(options.get("date", season.save.current_date()))
	if date == "":
		date = season.save.current_date()
	season.save.set_date(date)
	var player_id := str(options.get("player", ""))
	if player_id == "":
		player_id = str(PLDatabase.row(
			"SELECT id FROM player WHERE club_id = ? ORDER BY ovr DESC, id LIMIT 1;",
			[str(from_row["id"])]).get("id", ""))
	if player_id == "":
		season.close()
		return {"ok": false, "reason": "the from-club has no player"}
	var fee := int(options.get("fee", "5000000"))
	var wage := maxi(int(options.get("wage", "50000")), 1)
	var years := maxi(int(options.get("years", "3")), 1)
	var inject := str(options.get("inject", ""))
	var offer := {
		"player_id": player_id, "from_club_id": str(from_row["id"]),
		"to_club_id": str(to_row["id"]), "kind": str(options.get("kind", "permanent")),
		"fee": fee, "wage": wage, "years": years, "consent": 1, "date": date,
	}
	var reason := ""
	var deal_id := ""
	var state := ""
	var signed: Dictionary = {}
	var window_id := ""
	if str(options.get("force", "0")) != "0":
		signed = MarketDeals.force(season.save, offer, {"date": date, "inject": inject})
		deal_id = str(signed.get("deal_id", ""))
		state = str(signed.get("state", ""))
	else:
		var made := MarketDeals.propose(season.save, offer)
		deal_id = str(made.get("deal_id", ""))
		window_id = str(made.get("window_id", ""))
		if deal_id == "":
			season.close()
			return {"ok": false, "reason": str(made.get("reason", "propose_failed"))}
		print("proposed %s: %s -> %s for %s on %s" % [deal_id, str(from_row["id"]),
			str(to_row["id"]), MarketCurrency.format(fee), date])
		MarketDeals.negotiate(season.save, deal_id)
		var agreed := MarketDeals.agree(season.save, deal_id)
		print("agreed: %s (%s)" % [str(agreed.get("state", "")),
			str(agreed.get("reason", ""))])
		signed = MarketDeals.sign(season.save, deal_id,
			{"date": date, "inject": inject})
		state = str(signed.get("state", ""))
	reason = str(signed.get("reason", ""))
	var registration := _registration(deal_id)
	var cash := MarketFinance.cash(str(to_row["id"]))
	var headroom := MarketFinance.ffp_headroom(str(to_row["id"]))
	print("signed: %s; cash %s; registration %s" % [state,
		MarketCurrency.format(cash), registration])
	var result := {
		"ok": bool(signed.get("ok", false)), "state": state, "reason": reason,
		"deal": deal_id, "from": str(from_row["id"]), "to": str(to_row["id"]),
		"fee": fee, "registration": registration, "cash": cash, "headroom": headroom,
		"window_id": window_id if window_id != "" else str(PLDatabase.row(
			"SELECT window_id FROM deal WHERE id = ?;", [deal_id]).get("window_id", "")),
		"clears_on": str(signed.get("clears_on", "")),
		"rolled_back": bool(signed.get("rolled_back", false)),
	}
	season.close()
	return result


static func _registration(deal_id: String) -> String:
	if deal_id == "":
		return "none"
	var row := PLDatabase.row(
		"SELECT state FROM player_registration WHERE deal_id = ? "
		+ "ORDER BY rowid DESC LIMIT 1;", [deal_id])
	return str(row.get("state", "none"))


static func _club(token: String) -> Dictionary:
	if token == "":
		return {}
	var by_id := PLDatabase.row("SELECT * FROM club WHERE id = ?;", [token])
	if not by_id.is_empty():
		return by_id
	return PLDatabase.row(
		"SELECT * FROM club WHERE abbr = ? COLLATE NOCASE ORDER BY stub, id LIMIT 1;", [token])
