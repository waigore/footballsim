class_name WikiPlayer
extends RefCounted


static func page(player_id: String, mode: String = "SIMPLIFIED") -> Dictionary:
	var p := WikiModel.repo().player(player_id)
	if p.is_empty():
		return WikiLeague.page()
	var view := AttrView.normalize(mode)
	var club := WikiModel.repo().club(str(p["club_id"]))
	var season: Dictionary = p.get("season", {})
	var career: Dictionary = p.get("career", {})
	var sim: Dictionary = p.get("sim", {})
	var club_name := str(club.get("name", "")).to_upper()
	if club_name == "":
		club_name = "FREE AGENT"
	var identity := "%s  ·  %s  ·  #%d" % [club_name, str(p["pos"]), int(p["number"])]
	var extra: Array = []
	if int(p.get("age", 0)) > 0:
		extra.append("%d" % int(p["age"]))
	if str(p.get("nationality", "")) != "":
		extra.append(str(p["nationality"]).to_upper())
	if extra.size() > 0:
		identity += "  ·  " + "  ·  ".join(PackedStringArray(extra))
	var out := {
		"page": WikiModel.PLAYER,
		"id": player_id,
		"title": str(p["name"]).to_upper(),
		"eyebrow": str(club.get("abbr", "")),
		"subtitle": identity,
		"accent": club.get("color", Color.WHITE),
		"view": view,
		"blocks": [],
	}
	var summary: Array = [
		["OVERALL", str(int(p["ovr"])), true],
		["POSITION", str(p["pos"]), false],
		["ROLE", str(p["role"]), false],
		["HEIGHT", "%d CM" % int(p["height"]), false],
		["SQUAD", "STARTING XI" if str(p["squad"]) == "starter" else "BENCH", false],
	]
	var absence := WikiAbsence.status_of(str(p["club_id"]), player_id)
	if absence != "":
		summary.append(["STATUS", absence, false])
	out["blocks"].append({"k": "kv", "items": summary})
	out["blocks"].append({"k": "section", "text": "ATTRIBUTES"})
	out["blocks"].append({"k": "door", "items": [
		{"text": "SIMPLIFIED", "id": "attrs:SIMPLIFIED", "accent": WikiModel.hex(club.get("color", Color.WHITE)),
			"on": view == "SIMPLIFIED"},
		{"text": "FULL", "id": "attrs:FULL", "accent": WikiModel.hex(club.get("color", Color.WHITE)),
			"on": view == "FULL"},
	]})
	if view == "FULL":
		out["blocks"].append({
			"k": "grid", "cols": 3,
			"groups": AttrView.rows(str(p["role"]), p.get("subs", {})),
		})
		var extras := AttrView.extras(p)
		if not extras.is_empty():
			out["blocks"].append({"k": "section", "text": "CARD"})
			out["blocks"].append({"k": "kv", "items": extras})
	else:
		var bars: Array = []
		if str(p["role"]) == "GK":
			for pair in [["div", "DIVING"], ["han", "HANDLING"], ["kic", "KICKING"], ["ref", "REFLEXES"], ["spd", "SPEED"]]:
				bars.append([str(pair[1]), float(p["gk"].get(pair[0], 30)) / 100.0])
		else:
			for pair in [["pac", "PACE"], ["sho", "SHOOTING"], ["pas", "PASSING"], ["dri", "DRIBBLING"], ["def", "DEFENDING"], ["phy", "PHYSICAL"]]:
				bars.append([str(pair[1]), float(p[pair[0]]) / 100.0])
		out["blocks"].append({"k": "bars", "items": bars})
	out["blocks"].append_array(contract_blocks(player_id, club_name, str(p.get("club_id", ""))))
	out["blocks"].append_array(value_blocks(p, player_id))
	out["blocks"].append_array(loan_blocks(player_id))
	out["blocks"].append_array(transfer_blocks(player_id))
	var season_label := str(season.get("season_label", ""))
	var season_head := "SEASON"
	if season_label != "":
		season_head += "  ·  " + season_label
	out["blocks"].append({"k": "section", "text": season_head})
	if int(season.get("matches", 0)) > 0:
		out["blocks"].append({
			"k": "kv",
			"items": [
				["APPS", str(int(season["matches"])), true], ["STARTS", str(int(season["starts"])), false],
				["GOALS", count(season, "goals"), true], ["ASSISTS", count(season, "assists"), false],
				["MINUTES", str(int(season["minutes"])), false],
				["CARDS", "%d / %d" % [int(season["yellow"]), int(season["red"])], false],
			],
		})
	else:
		out["blocks"].append({"k": "note", "text": "NO SEASON STATISTICS YET"})
	out["blocks"].append({"k": "section", "text": "CAREER"})
	if int(career.get("matches", 0)) > 0:
		out["blocks"].append({
			"k": "kv",
			"items": [
				["APPS", str(int(career["matches"])), true], ["GOALS", count(career, "goals"), true],
				["ASSISTS", count(career, "assists"), false],
			],
		})
	else:
		out["blocks"].append({"k": "note", "text": "NO CAREER TOTALS YET"})
	var season_open := WikiModel.repo().season_active()
	out["blocks"].append({"k": "section", "text": WikiLedger.heading("IN FOOTBALLSIM")})
	out["blocks"].append(WikiLedger.player_line(sim, season_open))
	out["blocks"].append_array(WikiPlayerLog.blocks(player_id, str(p["club_id"])))
	if str(p.get("club_id", "")) != "":
		out["blocks"].append({"k": "chips", "items": [{
			"text": str(club.get("name", "")).to_upper(),
			"target": {"page": WikiModel.TEAM, "id": str(p["club_id"])},
			"accent": WikiModel.hex(club.get("color", Color.WHITE)),
		}]})
	out["blocks"].append(WikiCompetitions.link(str(club.get("competition", ""))))
	return out


static func contract_blocks(player_id: String, club_name: String, registered: String) -> Array:
	if not MarketContracts.available():
		return []
	var contract := MarketContracts.of_player(player_id)
	var out: Array = [{"k": "section", "text": "CONTRACT"}]
	if contract.is_empty():
		out.append({"k": "note", "text": "NO CONTRACT ON FILE"})
		return out
	var clause := int(contract.get("release_clause", 0))
	var items: Array = [
		["CLUB", "FREE AGENT" if registered == "" else club_name, true],
		["WAGE", MarketWages.weekly(int(contract.get("wage", 0))), true],
		["EXPIRES", str(contract.get("end_date", "")), false],
		["EMPLOYMENT", "FREE AGENT" if registered == "" else "CONTRACTED", false],
		["CLAUSE", "NONE" if clause <= 0 else MarketWages.money(clause), false],
	]
	var options := int(contract.get("option_years", 0))
	if options > 0:
		items.append(["OPTION", "+%d YR" % options, false])
	var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[str(contract.get("club_id", ""))])
	if not club.is_empty():
		var registration := MarketDealRecords.registration(player_id,
			str(club.get("competition_id", "")))
		if not registration.is_empty():
			var state := str(registration.get("state", "")).to_upper()
			if str(registration.get("reason", "")) != "":
				state += " · " + MarketDealCopy.reason(str(registration.get("reason", "")))
			items.append(["REGISTRATION", state, false])
	out.append({"k": "kv", "items": items})
	return out


static func count(source: Dictionary, key: String) -> String:
	var value := int(source.get(key, -1))
	return "—" if value < 0 else str(value)


static func value_blocks(player: Dictionary, player_id: String) -> Array:
	if int(player.get("ovr", 0)) <= 0:
		return []
	var contract := MarketContracts.of_player(player_id)
	var worth := MarketValuation.value(player, contract, _valuation_date())
	var wage := MarketValuation.weekly_wage(worth, int(contract.get("wage", 0)))
	var items: Array = [
		["VALUE", MarketCurrency.format(worth), true],
		["WAGE ASK", MarketWages.weekly(wage), false],
	]
	return [{"k": "section", "text": "VALUE"}, {"k": "kv", "items": items}]


static func _valuation_date() -> String:
	if LeagueSave.current == null:
		return ""
	return LeagueSave.current.current_date()


static func transfer_blocks(player_id: String) -> Array:
	if not MarketDeals.available():
		return []
	var deal := MarketDealRecords.last_for(player_id)
	if deal.is_empty():
		return []
	var out: Array = [{"k": "section", "text": "TRANSFER"}]
	var state := str(deal.get("state", ""))
	var items: Array = [
		["STATE", MarketDealCopy.state(state), true],
		["FROM", _club_name(str(deal.get("from_club_id", ""))), false],
		["TO", _club_name(str(deal.get("to_club_id", ""))), false],
		["FEE", MarketCurrency.format(int(deal.get("fee", 0))), false],
	]
	if state == MarketDealRecords.CLEARANCE_PENDING and str(deal.get("clears_on", "")) != "":
		items.append(["CLEARS", str(deal.get("clears_on", "")), false])
	items.append(["AGENT", MarketCurrency.format(int(deal.get("agent_fee", 0))), false])
	items.append(["BONUS", MarketCurrency.format(int(deal.get("signing_bonus", 0))), false])
	var extra := MarketAttribution.extras(deal)
	items.append(["SELL-ON", _sell_on_line(deal, extra.get("sell_on", {})), false])
	items.append(["SOLIDARITY", _solidarity_line(extra.get("solidarity", [])), false])
	var training: Dictionary = extra.get("training", {})
	if not training.is_empty() and int(training.get("amount", 0)) > 0:
		items.append(["TRAINING", MarketCurrency.format(int(training["amount"])), false])
	var reason := str(deal.get("reason", ""))
	if reason != "":
		items.append(["REASON", MarketDealCopy.reason(reason), false])
	out.append({"k": "kv", "items": items})
	return out


static func _sell_on_line(deal: Dictionary, share: Dictionary) -> String:
	if not share.is_empty() and int(share.get("amount", 0)) > 0:
		return "%s TO %s (%s)" % [MarketCurrency.format(int(share["amount"])),
			_club_name(str(share.get("club_id", ""))), _percent(float(share.get("rate", 0.0)))]
	var rate := float(deal.get("sell_on", 0.0))
	if rate > 0.0:
		return "%s ON NEXT SALE" % _percent(rate)
	return "NONE"


static func _solidarity_line(rows: Array) -> String:
	var total := 0
	for row in rows:
		total += int((row as Dictionary).get("amount", 0))
	if total <= 0:
		return "NONE"
	return MarketCurrency.format(total)


static func _percent(rate: float) -> String:
	return "%d%%" % int(round(rate * 100.0))


static func loan_blocks(player_id: String) -> Array:
	if not MarketLoans.available():
		return []
	var loan := MarketLoanRecords.active_for(player_id)
	if loan.is_empty():
		return []
	return [{"k": "section", "text": "LOAN"}, {"k": "kv", "items": [
		["PARENT", _club_name(str(loan.get("parent_club_id", ""))), false],
		["LOANEE", _club_name(str(loan.get("loanee_club_id", ""))), true],
		["WAGE SPLIT", "%s / %s" % [
			MarketWages.money(int(loan.get("wage_parent", 0))),
			MarketWages.money(int(loan.get("wage_loanee", 0)))], false],
		["ENDS", str(loan.get("end_date", "")), false],
		["BUY", _buy_label(str(loan.get("option_kind", "none")),
			int(loan.get("buy_fee", 0))), false],
		["TRIGGER", _trigger_label(str(loan.get("trigger_kind", "")),
			str(loan.get("trigger_value", ""))), false],
	]}]


static func _buy_label(kind: String, fee: int) -> String:
	if kind == "obligation":
		return "OBLIGATION %s" % MarketWages.money(fee)
	if kind == "option":
		return "OPTION %s" % MarketWages.money(fee)
	return "NONE"


static func _trigger_label(kind: String, value: String) -> String:
	if kind == "":
		return "—"
	if value == "":
		return kind.to_upper()
	return "%s %s" % [kind.to_upper(), value]


static func _club_name(club_id: String) -> String:
	if club_id == "":
		return "FREE AGENT"
	var club := WikiModel.repo().club(club_id)
	if club.is_empty():
		return club_id
	return str(club.get("name", club_id)).to_upper()
