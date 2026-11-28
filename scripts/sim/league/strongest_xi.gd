class_name StrongestXI
extends RefCounted


const FAMILY := {
	"GK": "GK",
	"RB": "FB", "LB": "FB",
	"RCB": "CB", "LCB": "CB", "CB": "CB",
	"RDM": "PIVOT", "LDM": "PIVOT", "CDM": "PIVOT", "CM": "PIVOT",
	"RW": "WING", "LW": "WING", "RM": "WING", "LM": "WING",
	"CAM": "CAM", "ST": "ST",
}

const EXACT_BONUS := 12.0
const FAMILY_BONUS := 5.0


static func pick(team: Dictionary, competition_id: String = "") -> Array:
	var pool: Array = []
	pool.append_array(team.get("starters", []))
	pool.append_array(team.get("bench", []))
	var out_ids := SeasonAvailability.unavailable(str(team.get("id", "")), competition_id)
	var fit: Array = []
	var unfit: Array = []
	for p in pool:
		if out_ids.has(str(p.get("id", ""))):
			unfit.append(p)
		else:
			fit.append(p)
	var slots: Array = TeamData.slots(str(team.get("formation", "4-2-3-1"))).keys()
	var used := {}
	var out: Array = []
	for slot in slots:
		var best := _best(fit, used, str(slot))
		if best.is_empty():
			continue
		used[str(best["id"])] = true
		out.append(best)


	if out.size() < slots.size():
		for slot in slots:
			if out.size() >= slots.size():
				break
			var spare := _best(unfit, used, str(slot))
			if spare.is_empty():
				continue
			used[str(spare["id"])] = true
			out.append(spare)
	return out

static func _best(pool: Array, used: Dictionary, slot: String) -> Dictionary:
	var best := {}
	var best_score := -1.0
	for p in pool:
		var id := str(p.get("id", ""))
		if id == "" or used.has(id):
			continue
		var role := str(p.get("role", ""))
		var score := float(p.get("ovr", 0))
		if role == slot:
			score += EXACT_BONUS
		elif str(FAMILY.get(role, role)) == str(FAMILY.get(slot, slot)):
			score += FAMILY_BONUS
		elif slot == "GK" or role == "GK":
			continue
		if score > best_score:
			best_score = score
			best = p
	return best


static func apply(club_id: String, competition_id: String = "") -> bool:
	var team := TeamData.get_team(club_id)
	var xi := pick(team, competition_id)
	if xi.size() < 11:
		return false
	var order := {}
	for i in range(xi.size()):
		order[str(xi[i]["id"])] = i + 1
	var rows := PLDatabase.rows("SELECT id FROM player WHERE club_id = ?;", [club_id])
	for i in range(rows.size()):
		var id := str(rows[i]["id"])
		var starter := order.has(id)
		PLDatabase.execute(
			"UPDATE player SET squad = ?, ord = ? WHERE id = ?;",
			["starters" if starter else "bench", int(order.get(id, 100 + i)), id],
		)
	return true


static func apply_all() -> int:
	var count := 0
	var ids: Array = []
	for cid in PLCompetitions.active_ids():
		ids.append_array(TeamData.team_ids(str(cid)))
	if ids.is_empty():
		ids = TeamData.team_ids()
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for id in ids:
		if apply(str(id)):
			count += 1
	PLDatabase.transaction("COMMIT;")
	PLRepository.shared().invalidate()
	return count
