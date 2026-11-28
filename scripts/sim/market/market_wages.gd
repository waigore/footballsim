class_name MarketWages
extends RefCounted


static func revenue_anchor(club: Dictionary) -> int:
	var capacity := int(club.get("capacity", 0))
	var competition_id := str(club.get("competition_id", ""))
	var fixtures := MarketRules.count("revenue", "home_fixtures", 19)
	var gate := float(capacity) * float(fixtures) * float(MarketRules.ticket_price(competition_id))
	return int(round(gate * MarketRules.revenue_multiplier(competition_id)))


static func wage_budget(club: Dictionary) -> int:
	return int(round(float(revenue_anchor(club)) * MarketRules.number("wage", "budget_share", 0.55)))


static func weight(ovr: int, floor_ovr: int = -1) -> float:
	var base := floor_ovr
	if base < 0:
		base = MarketRules.count("wage", "weight_floor", 30)
	return maxf(float(ovr - base), 1.0)


static func allocate(squad: Array, budget: int) -> Dictionary:
	var out := {}
	if squad.is_empty():
		return out
	var total := 0.0
	for player in squad:
		total += weight(int(player.get("ovr", 0)))
	var safety := MarketRules.number("wage", "safety", 0.96)
	var step := maxi(MarketRules.count("wage", "round_to", 10), 1)
	var weekly_budget := float(budget) * safety / 52.0
	var even := 1.0 / float(squad.size())
	for player in squad:
		var share := even
		if total > 0.0:
			share = weight(int(player.get("ovr", 0))) / total
		var weekly := int(round(weekly_budget * share / float(step))) * step
		out[str(player.get("id", ""))] = maxi(weekly, step)
	return out


static func money(amount: int) -> String:
	if amount >= 1_000_000:
		return "£%.1fM" % (float(amount) / 1_000_000.0)
	if amount >= 1_000:
		return "£%dK" % int(round(float(amount) / 1_000.0))
	return "£%d" % amount


static func weekly(amount: int) -> String:
	return "%s/WK" % money(amount)
