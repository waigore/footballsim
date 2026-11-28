class_name MarketAi
extends RefCounted


static func run_day(save: LeagueSave, day: String) -> Dictionary:
	var out := {"signed": 0, "failed": 0, "cleared": 0}
	if save == null or day == "" or not MarketDeals.available():
		return out
	out["cleared"] = resolve_clearances(day)
	var seed_value := _seed(save)
	var rate := MarketRules.number("ai", "deals_per_club_day", 0.028)
	if rate <= 0.0:
		return out
	for club_id in MarketTick.clubs():
		if _unit(seed_value, day, club_id, 1) >= rate:
			continue
		var verdict := _attempt(save, day, club_id, seed_value)
		if str(verdict.get("state", "")) == MarketDealRecords.SIGNED:
			out["signed"] = int(out["signed"]) + 1
		elif str(verdict.get("state", "")) != "":
			out["failed"] = int(out["failed"]) + 1
	return out


static func resolve_clearances(day: String) -> int:
	var cleared := 0
	for row in PLDatabase.rows(
			"SELECT id FROM deal WHERE state = 'clearance_pending' AND clears_on <= ? "
			+ "ORDER BY clears_on, id;", [day]):
		var out := MarketDeals.resolve_clearance(str(row.get("id", "")), day, {})
		if str(out.get("state", "")) == MarketDealRecords.SIGNED:
			cleared += 1
	return cleared


static func _attempt(save: LeagueSave, day: String, club_id: String, seed_value: int) -> Dictionary:
	var buyer := MarketDealRules.club_row(club_id)
	if buyer.is_empty():
		return {}
	var country := MarketWindows.country_of_club(buyer)
	if country == "" or not bool(MarketWindows.state(day, country).get("open", false)):
		return {}
	var profile := MarketNeeds.profile(club_id)
	var wants := MarketNeeds.wants(profile)
	if wants.is_empty():
		return {}
	var want: Dictionary = wants[0]
	var group := str(want.get("group", ""))
	var severity_value := float(want.get("severity", 0.0))
	var budget := MarketNeeds.budget(club_id)
	if budget <= 0:
		return {}
	var ceiling_ovr := _ceiling_ovr(profile, group)
	var pick := _pick_candidate(save, day, club_id, group, ceiling_ovr, budget,
		int(profile.get("median", 0)), seed_value)
	if pick.is_empty():
		return {}
	return _deal(save, day, club_id, pick, severity_value, budget, seed_value)


static func _pick_candidate(save: LeagueSave, day: String, club_id: String, group: String,
		ceiling_ovr: int, budget: int, median: int, seed_value: int) -> Dictionary:
	for player_id in MarketShortlist.candidates(save, day, club_id, group, ceiling_ovr):
		var player := PLRepository.shared().player(str(player_id))
		if player.is_empty():
			continue
		var seller := str(player.get("club_id", ""))
		if seller == "" or seller == club_id:
			continue
		var contract := MarketDealRecords.active_contract(str(player_id))
		var worth := MarketValuation.value(player, contract, day)
		if worth <= 0 or worth > int(float(budget) * 1.2):
			continue
		return {
			"player": player, "player_id": str(player_id), "seller": seller,
			"contract": contract, "value": worth,
		}
	return {}


static func _deal(save: LeagueSave, day: String, club_id: String, pick: Dictionary,
		severity_value: float, budget: int, seed_value: int) -> Dictionary:
	var player: Dictionary = pick["player"]
	var player_id := str(pick["player_id"])
	var seller := str(pick["seller"])
	var worth := int(pick["value"])
	var contract: Dictionary = pick["contract"]
	var group := MarketNeeds.group_of(str(player.get("pos", "")))
	var seller_depth := MarketNeeds.group_depth(seller, group)
	var required := int(MarketNeeds.required().get(group, 0))
	var rank := MarketNeeds.rank_of(seller, group, int(player.get("ovr", 0)))
	var ask_mult := MarketNeeds.seller_mult(seller_depth, required, rank)
	var bid_mult := 0.94 + 0.16 * _unit(seed_value, day, player_id, 2)
	if ask_mult > bid_mult + 0.12:
		return {}
	var ceiling := MarketNeeds.need_ceiling(severity_value)
	var fee := int(round(float(worth) * minf(bid_mult, ceiling)))
	var fee_cap := int(float(budget) * 0.85)
	fee = mini(fee, fee_cap)
	if fee < MarketRules.count("deal", "fee_min", 0):
		return {}
	var current_wage := int(contract.get("wage", 0))
	var wage := MarketValuation.weekly_wage(worth, current_wage)
	var terms := {
		"fee": fee, "wage": wage, "years": _years(seed_value, day, player_id),
		"agent_fee": int(round(float(fee) * 0.05)), "signing_bonus": 0, "sell_on": 0.0,
	}
	if not _consents(day, club_id, player, current_wage, wage, seed_value):
		return {}
	var opened := MarketDeals.propose(save, seller, club_id, player_id, terms, day)
	var deal_id := str(opened.get("deal", ""))
	if deal_id == "":
		return {}
	var agreed := MarketDeals.agree(deal_id, day, {})
	if str(agreed.get("state", "")) == MarketDealRecords.CLEARANCE_PENDING:
		_forget(seller, club_id)
		return {"deal": deal_id, "state": MarketDealRecords.CLEARANCE_PENDING}
	if not bool(agreed.get("ok", false)):
		return {"deal": deal_id, "state": MarketDealRecords.FAILED}
	var done := MarketDeals.seal(deal_id, day, {})
	_forget(seller, club_id)
	return done


static func _forget(seller: String, buyer: String) -> void:
	MarketNeeds.forget(seller)
	MarketNeeds.forget(buyer)
	MarketShortlist.rebuild_for(seller, buyer)


static func _consents(day: String, club_id: String, player: Dictionary,
		current_wage: int, wage: int, seed_value: int) -> bool:
	var buyer_rep := MarketFinance.reputation(club_id)
	var ovr := int(player.get("ovr", 0))
	var wanted_rep := int(20.0 + float(maxi(ovr - 60, 0)) * 2.2)
	var uplift := 1.0
	if current_wage > 0:
		uplift = float(wage) / float(current_wage)
	if buyer_rep < wanted_rep and uplift < 1.30:
		if _unit(seed_value, day, str(player.get("id", "")), 3) < 0.75:
			return false
	return true


static func _ceiling_ovr(profile: Dictionary, group: String) -> int:
	var median := int(profile.get("median", 0))
	var groups: Dictionary = profile.get("groups", {})
	var row: Dictionary = groups.get(group, {})
	var best := int(row.get("best", 0))
	var gap := MarketRules.count("need", "quality_gap", 3)
	return maxi(median + gap + 2, best + gap + 2)


static func _years(seed_value: int, day: String, player_id: String) -> int:
	var low := maxi(MarketRules.count("deal", "years_min", 1), 1)
	var high := maxi(MarketRules.count("deal", "years_max", 5), low)
	var span := high - low + 1
	return low + MarketSeed.mix(seed_value, "%s|%s" % [day, player_id], 4) % span


static func _unit(seed_value: int, day: String, key: String, salt: int) -> float:
	return MarketSeed.unit(seed_value, "market|%s|%s" % [day, key], salt)


static func _seed(save: LeagueSave) -> int:
	if save == null:
		return 0
	return absi(int(str(save.meta.get("seed", "0"))))
