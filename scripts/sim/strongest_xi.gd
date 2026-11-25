class_name StrongestXI
extends RefCounted

## The eleven a club fields when nobody is picking a team: the best eligible
## player for every slot of the club's preferred formation.
##
## "Eligible" means the role named by the shape first, then the same line of the
## team (a centre-back who can play either side, a pivot on either foot), then
## the best remaining player. Ability is the snapshot's OVR; a specialist keeps
## a bonus over a better player out of position, so a formation never fields a
## striker at centre-back while a defender is on the bench.
##
## The chosen XI is written into the save's own player rows (starters/bench and
## order), which is why the match engine and the Poisson path field the same
## eleven: both read the save.

## Roles that can cover each other before ability decides.
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

## Best XI for a team dictionary (starters + bench), in formation-slot order.
##
## A player the season has ruled out — injured or suspended — is skipped, so the
## eleven a club fields is its strongest *available* side (#155, #156). A club
## that cannot field eleven fit bodies fills the gaps with whoever it has, which
## is what a real squad does rather than playing short from kick-off.
static func pick(team: Dictionary) -> Array:
	var pool: Array = []
	pool.append_array(team.get("starters", []))
	pool.append_array(team.get("bench", []))
	var out_ids := SeasonAvailability.unavailable(str(team.get("id", "")))
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
	# Short of eleven: the remaining slots take the best ruled-out bodies, so
	# the side still kicks off with eleven and the briefing still says why.
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
			# Never let an outfielder cover in goal (or a keeper cover outfield).
			continue
		if score > best_score:
			best_score = score
			best = p
	return best

## Rewrite one club's squad flags in the bound save: the XI becomes the starting
## eleven in slot order, everyone else is ordered on the bench.
static func apply(club_id: String) -> bool:
	var team := TeamData.get_team(club_id)
	var xi := pick(team)
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

## Apply to every club in the bound save; called once when a season is created
## so both outcome paths field the same elevens all season.
static func apply_all() -> int:
	var count := 0
	var ids: Array = []
	for row in PLRepository.shared().active_competitions():
		ids.append_array(TeamData.team_ids(str(row["id"])))
	if ids.is_empty():
		ids = TeamData.team_ids()
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for id in ids:
		if apply(str(id)):
			count += 1
	PLDatabase.transaction("COMMIT;")
	PLRepository.shared().invalidate()
	return count
