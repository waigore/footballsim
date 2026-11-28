class_name MarketAttribution
extends RefCounted


const FIRST_MOVE_KINDS := ["permanent", "loan_converted"]


static func release_clause(player_id: String) -> int:
	if player_id == "" or not MarketContracts.available():
		return 0
	return int(MarketContracts.of_player(player_id).get("release_clause", 0))


static func clause_met(player_id: String, fee: int) -> bool:
	var clause := release_clause(player_id)
	return clause > 0 and fee >= clause


static func extras(deal: Dictionary) -> Dictionary:
	var player_id := str(deal.get("player_id", ""))
	var fee := int(deal.get("fee", 0))
	var seller := str(deal.get("from_club_id", ""))
	var buyer := str(deal.get("to_club_id", ""))
	return {
		"sell_on": sell_on_share(player_id, seller, fee, str(deal.get("id", ""))),
		"solidarity": solidarity_shares(player_id, fee),
		"training": training_due(player_id, buyer, fee),
	}


static func buyer_cost(deal: Dictionary) -> int:
	var extra := extras(deal)
	var total := int(deal.get("fee", 0)) + int(deal.get("agent_fee", 0)) \
		+ int(deal.get("signing_bonus", 0))
	total += int((extra.get("training", {}) as Dictionary).get("amount", 0))
	for row in extra.get("solidarity", []):
		total += int((row as Dictionary).get("amount", 0))
	return total


static func sell_on_share(player_id: String, seller: String, fee: int, exclude: String) -> Dictionary:
	if player_id == "" or seller == "" or fee <= 0:
		return {}
	var row := PLDatabase.row(
		"SELECT from_club_id, sell_on, id FROM deal WHERE player_id = ? AND to_club_id = ? "
		+ "AND state = 'signed' AND sell_on > 0 AND kind IN ('permanent', 'loan_converted') "
		+ "AND id <> ? ORDER BY signed_on DESC, rowid DESC LIMIT 1;",
		[player_id, seller, exclude])
	if row.is_empty():
		return {}
	var former := str(row.get("from_club_id", ""))
	var rate := float(row.get("sell_on", 0.0))
	if former == "" or former == seller or rate <= 0.0:
		return {}
	return {"club_id": former, "rate": rate, "amount": int(round(float(fee) * rate))}


static func solidarity_shares(player_id: String, fee: int) -> Array:
	if player_id == "" or fee <= 0:
		return []
	var total := int(round(float(fee) * MarketRules.number("attribution", "solidarity_share", 0.05)))
	if total <= 0:
		return []
	var weights := _spell_weights(player_id)
	if weights.is_empty():
		return []
	var sum := 0.0
	for club_id in weights:
		sum += float(weights[club_id])
	if sum <= 0.0:
		return []
	return _distribute(weights, sum, total)


static func training_due(player_id: String, buyer: String, fee: int) -> Dictionary:
	if player_id == "" or fee <= 0 or not _first_move(player_id):
		return {}
	if not _has_youth_history(player_id):
		return {}
	var age := int(PLDatabase.row("SELECT age FROM player WHERE id = ?;", [player_id]).get("age", 0))
	var home := str(PLDatabase.row("SELECT homegrown_club_id FROM player WHERE id = ?;",
		[player_id]).get("homegrown_club_id", ""))
	if home == "" or home == buyer:
		return {}
	for band in MarketRules.section("attribution").get("training_bands", []):
		if age <= int((band as Dictionary).get("to_age", 0)):
			return {"club_id": home, "amount": int((band as Dictionary).get("amount", 0)),
				"age": age}
	return {}


static func _has_youth_history(player_id: String) -> bool:
	return not PLDatabase.row(
		"SELECT id FROM player_history WHERE player_id = ? AND kind = 'spell' LIMIT 1;",
		[player_id]).is_empty()


static func apply(deal: Dictionary, date: String) -> void:
	var player_id := str(deal.get("player_id", ""))
	var seller := str(deal.get("from_club_id", ""))
	var buyer := str(deal.get("to_club_id", ""))
	var deal_id := str(deal.get("id", ""))
	var extra := extras(deal)
	var share: Dictionary = extra.get("sell_on", {})
	if not share.is_empty() and int(share.get("amount", 0)) > 0:
		MarketFinance.post(seller, date, MarketFinance.KIND_SELL_ON, -int(share["amount"]),
			str(share["club_id"]), player_id, deal_id)
		MarketFinance.post(str(share["club_id"]), date, MarketFinance.KIND_SELL_ON,
			int(share["amount"]), seller, player_id, deal_id)
	for row in extra.get("solidarity", []):
		var amount := int((row as Dictionary).get("amount", 0))
		if amount <= 0:
			continue
		MarketFinance.post(buyer, date, MarketFinance.KIND_SOLIDARITY, -amount,
			str(row.get("club_id", "")), player_id, deal_id)
		MarketFinance.post(str(row.get("club_id", "")), date, MarketFinance.KIND_SOLIDARITY,
			amount, buyer, player_id, deal_id)
	var training: Dictionary = extra.get("training", {})
	if not training.is_empty() and int(training.get("amount", 0)) > 0:
		MarketFinance.post(buyer, date, MarketFinance.KIND_TRAINING, -int(training["amount"]),
			str(training.get("club_id", "")), player_id, deal_id)
		MarketFinance.post(str(training.get("club_id", "")), date, MarketFinance.KIND_TRAINING,
			int(training["amount"]), buyer, player_id, deal_id)


static func _spell_weights(player_id: String) -> Dictionary:
	var weights := {}
	var birth := str(PLDatabase.row("SELECT date_of_birth FROM player WHERE id = ?;",
		[player_id]).get("date_of_birth", ""))
	if birth == "":
		return weights
	var from_age := MarketRules.count("attribution", "solidarity_from_age", 12)
	var to_age := MarketRules.count("attribution", "solidarity_to_age", 23)
	for row in PLDatabase.rows(
			"SELECT club_id, from_date, to_date FROM player_history WHERE player_id = ? "
			+ "AND kind = 'spell';", [player_id]):
		var club_id := str(row.get("club_id", ""))
		if club_id == "":
			continue
		var years := _overlap_years(birth, str(row.get("from_date", "")),
			str(row.get("to_date", "")), from_age, to_age)
		if years <= 0.0:
			continue
		weights[club_id] = float(weights.get(club_id, 0.0)) + years
	return weights


static func _overlap_years(birth: String, from_date: String, to_date: String,
		from_age: int, to_age: int) -> float:
	if from_date == "" or to_date == "":
		return 0.0
	var birth_days := FixtureCalendar.days_from(birth)
	if birth_days <= 0:
		return 0.0
	var start_days := FixtureCalendar.days_from(from_date)
	var end_days := FixtureCalendar.days_from(to_date)
	var from_days := maxi(start_days, birth_days + from_age * 365)
	var to_days := mini(end_days, birth_days + (to_age + 1) * 365)
	if to_days <= from_days:
		return 0.0
	return float(to_days - from_days) / 365.25


static func _distribute(weights: Dictionary, total_weight: float, total: int) -> Array:
	var keys: Array = weights.keys()
	keys.sort()
	var out: Array = []
	var assigned := 0
	var remainders: Array = []
	for club_id in keys:
		var exact := float(total) * float(weights[club_id]) / total_weight
		var amount := int(floor(exact))
		assigned += amount
		remainders.append({"club_id": club_id, "frac": exact - float(amount), "amount": amount})
	remainders.sort_custom(func(a, b): return float(a["frac"]) > float(b["frac"]))
	var leftover := total - assigned
	for i in range(remainders.size()):
		if leftover <= 0:
			break
		(remainders[i] as Dictionary)["amount"] = int(remainders[i]["amount"]) + 1
		leftover -= 1
	for row in remainders:
		out.append({"club_id": str(row["club_id"]), "amount": int(row["amount"])})
	return out


static func _first_move(player_id: String) -> bool:
	var marks := PackedStringArray()
	for kind in FIRST_MOVE_KINDS:
		marks.append("?")
	var bindings: Array = [player_id]
	bindings.append_array(FIRST_MOVE_KINDS)
	var count := int(PLDatabase.row(
		"SELECT COUNT(*) AS n FROM deal WHERE player_id = ? AND state = 'signed' AND kind IN ("
		+ ", ".join(marks) + ");", bindings).get("n", 0))
	return count == 0
