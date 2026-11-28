class_name MarketNeeds
extends RefCounted


const GROUPS := {
	"GK": ["GK"],
	"DEF": ["CB", "RCB", "LCB", "RB", "LB"],
	"MID": ["CDM", "RDM", "LDM", "CM", "CAM", "RM", "LM"],
	"ATT": ["RW", "LW", "ST"],
}

static var _medians := {}
static var _profiles := {}


static func invalidate() -> void:
	_medians.clear()
	_profiles.clear()


static func forget(club_id: String) -> void:
	if club_id == "":
		return
	var prefix := PLDatabase.current_path() + "|"
	_profiles.erase(prefix + club_id)


static func group_of(pos: String) -> String:
	for group in GROUPS.keys():
		if (GROUPS[group] as Array).has(pos):
			return str(group)
	return "MID"


static func groups() -> Array:
	return GROUPS.keys()


static func required() -> Dictionary:
	var found: Variant = MarketRules.section("need").get("required", {})
	return found if found is Dictionary else {}


static func tier_median(competition_id: String) -> int:
	if competition_id == "":
		return 0
	var key := PLDatabase.current_path() + "|" + competition_id
	if _medians.has(key):
		return int(_medians[key])
	var rows := PLDatabase.rows(
		"SELECT p.ovr FROM player p JOIN club c ON c.id = p.club_id "
		+ "WHERE c.competition_id = ? ORDER BY p.ovr;", [competition_id])
	var value := 0
	if not rows.is_empty():
		value = int(rows[int(rows.size() / 2)].get("ovr", 0))
	_medians[key] = value
	return value


static func severity(depth: int, best: int, need: int, median: int) -> float:
	var short := 0.0
	if need > 0 and depth < need:
		short = float(need - depth) / float(need)
	var quality := 0.0
	var gap := float(maxi(MarketRules.count("need", "quality_gap", 3), 1))
	if depth <= 0:
		quality = 1.0
	elif median > 0 and best < median:
		quality = clampf(float(median - best) / gap, 0.0, 1.0)
	var cap := MarketRules.number("need", "severity_cap", 1.0)
	return clampf(short * 0.6 + quality * 0.4, 0.0, cap)


static func profile(club_id: String) -> Dictionary:
	if club_id == "":
		return {}
	var key := PLDatabase.current_path() + "|" + club_id
	if _profiles.has(key):
		return _profiles[key]
	var club := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	if club.is_empty():
		return {}
	var competition_id := str(club.get("competition_id", ""))
	var median := tier_median(competition_id)
	var need := required()
	var depth := {}
	var best := {}
	for group in GROUPS.keys():
		depth[group] = 0
		best[group] = 0
	for row in PLDatabase.rows("SELECT pos, ovr FROM player WHERE club_id = ?;", [club_id]):
		var group := group_of(str(row.get("pos", "")))
		depth[group] = int(depth[group]) + 1
		best[group] = maxi(int(best[group]), int(row.get("ovr", 0)))
	var out := {}
	for group in GROUPS.keys():
		var want := int(need.get(group, 0))
		out[group] = {
			"depth": int(depth[group]), "best": int(best[group]), "required": want,
			"severity": severity(int(depth[group]), int(best[group]), want, median),
		}
	var result := {"competition": competition_id, "median": median, "groups": out}
	_profiles[key] = result
	return result


static func wants(profile_row: Dictionary) -> Array:
	var out: Array = []
	var groups: Dictionary = profile_row.get("groups", {})
	for group in groups.keys():
		var row: Dictionary = groups[group]
		var severity_value := float(row.get("severity", 0.0))
		if severity_value <= 0.0:
			continue
		out.append({
			"group": str(group), "severity": severity_value,
			"depth": int(row.get("depth", 0)), "required": int(row.get("required", 0)),
			"best": int(row.get("best", 0)),
		})
	out.sort_custom(func(a, b): return float(a["severity"]) > float(b["severity"]))
	return out


static func budget(club_id: String) -> int:
	if club_id == "":
		return 0
	var finance := MarketFinance.club(club_id)
	if finance.is_empty():
		return 0
	var reserve := int(round(float(finance.get("revenue_base", 0))
		* MarketRules.number("need", "reserve_share", 0.10)))
	return maxi(int(finance.get("cash", 0)) - reserve, 0)


static func need_ceiling(severity_value: float) -> float:
	var low := MarketRules.number("ai", "need_ceiling_min", 1.0)
	var high := maxf(MarketRules.number("ai", "need_ceiling_max", 1.35), low)
	return low + clampf(severity_value, 0.0, 1.0) * (high - low)


static func seller_mult(depth: int, required_count: int, rank: int) -> float:
	var low := MarketRules.number("ai", "seller_floor_min", 0.75)
	var high := maxf(MarketRules.number("ai", "seller_floor_max", 1.15), low)
	var surplus := (depth - 1) - required_count
	var mult := 1.0 - 0.08 * clampf(float(surplus), 0.0, 3.0)
	if rank <= 1:
		mult += 0.15
	elif rank == 2:
		mult += 0.07
	elif rank == 3:
		mult += 0.02
	return clampf(mult, low, high)


static func rank_of(club_id: String, group: String, ovr: int) -> int:
	var ranks := 1
	for row in PLDatabase.rows(
			"SELECT ovr, pos FROM player WHERE club_id = ? AND id <> '';", [club_id]):
		if group_of(str(row.get("pos", ""))) != group:
			continue
		if int(row.get("ovr", 0)) > ovr:
			ranks += 1
	return ranks


static func group_depth(club_id: String, group: String) -> int:
	var count := 0
	for row in PLDatabase.rows("SELECT pos FROM player WHERE club_id = ?;", [club_id]):
		if group_of(str(row.get("pos", ""))) == group:
			count += 1
	return count
