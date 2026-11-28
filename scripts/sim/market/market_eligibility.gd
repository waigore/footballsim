class_name MarketEligibility
extends RefCounted


const ITALY := ["SA", "SB"]


static func slots() -> int:
	return MarketRules.count("registration", "slots", 25)


static func homegrown_min() -> int:
	return MarketRules.count("registration", "homegrown_min", 8)


static func u21_age() -> int:
	return MarketRules.count("registration", "u21_age", 21)


static func association_min() -> int:
	return MarketRules.count("registration", "uefa_association_trained_min", 4)


static func italy_club_min() -> int:
	return MarketRules.count("registration", "italy_club_trained_min", 4)


static func italy_association_min() -> int:
	return MarketRules.count("registration", "italy_association_trained_min", 8)


static func association_of_club(club: Dictionary) -> String:
	return MarketWindows.country_of_club(club)


static func association_of_nationality(nationality: String) -> String:
	match nationality.strip_edges():
		"England", "ENG":
			return "ENG"
		"Spain", "ESP":
			return "ESP"
		"Germany", "GER":
			return "GER"
		"Italy", "ITA":
			return "ITA"
	return ""


static func eu_nationalities() -> Dictionary:
	var out := {}
	for name in MarketRules.section("registration").get("eu_nationalities", []):
		out[str(name)] = true
	for pair in [["England", "ENG"], ["Spain", "ESP"], ["Germany", "GER"], ["Italy", "ITA"]]:
		out[str(pair[0])] = true
		out[str(pair[1])] = true
	return out


static func is_non_eu(nationality: String, association: String) -> bool:
	var key := nationality.strip_edges()
	if key == "":
		return false
	if association_of_nationality(key) == association:
		return false
	return not eu_nationalities().has(key)


static func is_association_trained(nationality: String, association: String) -> bool:
	return association != "" and association_of_nationality(nationality) == association


static func is_homegrown(player: Dictionary, club_id: String) -> bool:
	var trained := str(player.get("homegrown_club_id", ""))
	return trained != "" and trained == club_id


static func is_u21(player: Dictionary) -> bool:
	var age := int(player.get("age", 0))
	return age > 0 and age < u21_age()


static func non_eu_cap(association: String) -> int:
	var caps: Variant = MarketRules.section("registration").get("non_eu_cap", {})
	if caps is Dictionary:
		return int((caps as Dictionary).get(association, -1))
	return -1


static func permit_threshold(association: String) -> int:
	var table: Variant = MarketRules.section("registration").get("permit_min_ovr", {})
	if table is Dictionary:
		return int((table as Dictionary).get(association, 0))
	return 0


static func is_uefa(competition_id: String) -> bool:
	return LeagueUefa.is_continental(competition_id)


static func is_italy(competition_id: String) -> bool:
	return ITALY.has(competition_id)


static func is_domestic(competition_id: String) -> bool:
	return LeagueTiers.order().has(competition_id)


static func tally(players: Array, club_id: String, competition_id: String,
		association: String) -> Dictionary:
	var out := {"slots": 0, "homegrown": 0, "association": 0, "non_eu": 0, "u21": 0,
		"club_trained": 0}
	for raw in players:
		var row: Dictionary = raw
		var nationality := str(row.get("nationality", ""))
		var owned := is_homegrown(row, club_id)
		if is_u21(row):
			out["u21"] = int(out["u21"]) + 1
		else:
			out["slots"] = int(out["slots"]) + 1
		if owned:
			out["homegrown"] = int(out["homegrown"]) + 1
			out["club_trained"] = int(out["club_trained"]) + 1
		if owned or is_association_trained(nationality, association):
			out["association"] = int(out["association"]) + 1
		if is_non_eu(nationality, association):
			out["non_eu"] = int(out["non_eu"]) + 1
	return out


static func breaches(competition_id: String, association: String, counts: Dictionary) -> Array:
	var reasons: Array = []
	var size := int(counts.get("slots", 0))
	if size > slots():
		reasons.append("list_full")
	if is_italy(competition_id):
		if int(counts.get("club_trained", 0)) < italy_club_min():
			reasons.append("italy_club_min")
		if int(counts.get("association", 0)) < italy_association_min():
			reasons.append("italy_association_min")
		return reasons
	if is_uefa(competition_id):
		if int(counts.get("association", 0)) < association_min():
			reasons.append("association_trained_min")
		return reasons
	if is_domestic(competition_id):
		if int(counts.get("homegrown", 0)) < homegrown_min():
			reasons.append("homegrown_min")
		var cap := non_eu_cap(association)
		if cap >= 0 and int(counts.get("non_eu", 0)) > cap:
			reasons.append("non_eu_cap")
	return reasons


static func admits(competition_id: String, association: String, counts: Dictionary,
		incoming: Dictionary) -> Array:
	var after: Dictionary = counts.duplicate()
	if not is_u21(incoming):
		after["slots"] = int(after.get("slots", 0)) + 1
	if is_homegrown(incoming, str(incoming.get("club_id", ""))):
		after["homegrown"] = int(after.get("homegrown", 0)) + 1
		after["club_trained"] = int(after.get("club_trained", 0)) + 1
	if is_association_trained(str(incoming.get("nationality", "")), association) \
			or is_homegrown(incoming, str(incoming.get("club_id", ""))):
		after["association"] = int(after.get("association", 0)) + 1
	if is_non_eu(str(incoming.get("nationality", "")), association):
		after["non_eu"] = int(after.get("non_eu", 0)) + 1
	return bands(competition_id, association, after)


static func bands(competition_id: String, association: String, counts: Dictionary) -> Array:
	var reasons: Array = []
	var size := int(counts.get("slots", 0))
	if size > slots():
		reasons.append("list_full")
	if is_italy(competition_id):
		if size - int(counts.get("club_trained", 0)) > slots() - italy_club_min():
			reasons.append("italy_club_min")
		if size - int(counts.get("association", 0)) > slots() - italy_association_min():
			reasons.append("italy_association_min")
		return reasons
	if is_uefa(competition_id):
		if size - int(counts.get("association", 0)) > slots() - association_min():
			reasons.append("association_trained_min")
		return reasons
	if is_domestic(competition_id):
		if size - int(counts.get("homegrown", 0)) > slots() - homegrown_min():
			reasons.append("homegrown_min")
		var cap := non_eu_cap(association)
		if cap >= 0 and int(counts.get("non_eu", 0)) > cap:
			reasons.append("non_eu_cap")
	return reasons
