class_name MatchEvents
extends RefCounted


const GOAL_SHARE := {
	"ST": 0.44, "LW": 0.15, "RW": 0.15, "CAM": 0.11,
	"LDM": 0.035, "RDM": 0.035, "CDM": 0.035, "CM": 0.05,
	"LB": 0.015, "RB": 0.015, "LCB": 0.005, "RCB": 0.005,
	"CB": 0.005, "LM": 0.03, "RM": 0.03, "GK": 0.001,
}

const ASSIST_SHARE := {
	"ST": 0.12, "LW": 0.18, "RW": 0.18, "CAM": 0.20,
	"LDM": 0.08, "RDM": 0.08, "CDM": 0.08, "CM": 0.10,
	"LB": 0.06, "RB": 0.06, "LCB": 0.01, "RCB": 0.01,
	"CB": 0.01, "LM": 0.05, "RM": 0.05, "GK": 0.01,
}

const CARD_SHARE := {
	"ST": 0.03, "LW": 0.04, "RW": 0.04, "CAM": 0.07,
	"LDM": 0.16, "RDM": 0.16, "CDM": 0.16, "CM": 0.12,
	"LB": 0.09, "RB": 0.09, "LCB": 0.13, "RCB": 0.13,
	"CB": 0.13, "LM": 0.03, "RM": 0.03, "GK": 0.01,
}


const YELLOWS_PER_SIDE := 1.8
const RED_CHANCE := 0.04

const ASSIST_CHANCE := 0.62


const PENALTY_SHARE := 0.12

const MATCH_MINUTES := 90


static func side(seed: int, fixture_id: String, club_id: String, xi: Array, goals: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var used_minutes := {}


	var exit_rows: Array = []
	if rng.randf() < RED_CHANCE:
		var minute := _minute(rng)
		var sent_off := pick(xi, CARD_SHARE, "def", rng)
		if not sent_off.is_empty():
			exit_rows.append(_row(fixture_id, minute, "red", sent_off, club_id))


	if rng.randf() < SeasonAvailability.INJURY_RATE:
		var minute := _minute(rng)
		var hurt := pick(xi, CARD_SHARE, "phy", rng)
		if not hurt.is_empty():
			exit_rows.append(_row(fixture_id, minute, "injury", hurt, club_id))


	var exits := {}
	for row in exit_rows:
		var id := str(row["player_id"])
		if not exits.has(id) or int(row["minute"]) < int(exits[id]["minute"]):
			exits[id] = row
	var gone := {}
	for id in exits.keys():
		gone[id] = int(exits[id]["minute"])
		out.append(exits[id])
	for i in range(maxi(goals, 0)):
		var minute := _minute(rng)
		var scorer := pick(xi, GOAL_SHARE, "sho", rng, "", gone, minute)
		if scorer.is_empty():
			continue
		var row := _row(fixture_id, minute, "goal", scorer, club_id)


		if rng.randf() < PENALTY_SHARE:
			row["penalty"] = true
			out.append(row)
			continue
		var assist_row := {}
		if rng.randf() < ASSIST_CHANCE:
			var helper := pick(xi, ASSIST_SHARE, "pas", rng, str(scorer["id"]), gone, minute)
			if not helper.is_empty():


				row["assist_id"] = str(helper["id"])
				row["assist_name"] = str(helper.get("name", ""))
				assist_row = _row(fixture_id, minute, "assist", helper, club_id)
		out.append(row)
		if not assist_row.is_empty():
			out.append(assist_row)
	var yellows := clampi(int(round(YELLOWS_PER_SIDE + (rng.randf() - 0.5) * 2.0)), 0, 6)
	for i in range(yellows):


		var minute := _minute(rng)
		var booked := {}
		for attempt in range(8):
			booked = pick(xi, CARD_SHARE, "def", rng, "", gone, minute)
			if booked.is_empty():
				break
			if not used_minutes.has("%d/%s" % [minute, str(booked["id"])]):
				break
			booked = {}
			minute = _minute(rng)
		if booked.is_empty():
			continue
		used_minutes["%d/%s" % [minute, str(booked["id"])]] = true
		out.append(_row(fixture_id, minute, "yellow", booked, club_id))
	out.sort_custom(func(a, b): return int(a["minute"]) < int(b["minute"]))
	return out


static func pick(xi: Array, shares: Dictionary, ability: String, rng: RandomNumberGenerator,
		skip_id: String = "", gone: Dictionary = {}, minute: int = 0) -> Dictionary:
	var weights: Array = []
	var total := 0.0
	for p in xi:
		var id := str(p.get("id", ""))
		if id == "" or id == skip_id or _off(gone, id, minute):
			weights.append(0.0)
			continue
		var role := str(p.get("role", ""))
		var share := float(shares.get(role, 0.01))
		var skill := float(p.get(ability, 50))
		var w := share * (0.55 + skill / 100.0)
		weights.append(w)
		total += w
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	var acc := 0.0
	var last := -1
	for i in range(weights.size()):
		if float(weights[i]) <= 0.0:
			continue
		last = i
		acc += float(weights[i])
		if roll <= acc:
			return xi[i]
	if last < 0:
		return {}
	return xi[last]


static func _off(gone: Dictionary, id: String, minute: int) -> bool:
	return gone.has(id) and int(gone[id]) <= minute

static func _minute(rng: RandomNumberGenerator) -> int:
	return rng.randi_range(1, MATCH_MINUTES)

static func _row(fixture_id: String, minute: int, kind: String, player: Dictionary, club_id: String) -> Dictionary:
	return {
		"fixture_id": fixture_id,
		"minute": minute,
		"kind": kind,
		"player_id": str(player.get("id", "")),
		"club_id": club_id,
		"detail": str(player.get("name", "")),
		"player_name": str(player.get("name", "")),
	}
