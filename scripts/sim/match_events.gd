class_name MatchEvents
extends RefCounted

## Synthetic match events for a Poisson auto-simmed fixture.
##
## The scoreline comes from the outcome model; this turns it into the report a
## player reads: who scored, who set it up, who was booked. Real leagues put
## goals where the goalscorers are, so a side's strike share is a table of
## position priors, lightly adjusted by finishing ability. Every draw is seeded
## from the save's own RNG seed and the fixture id, so reopening a save and
## replaying a fixture reproduces the same report.
##
## Priors (share of a side's goals, before ability weighting), inspired by a
## real Premier League season's distribution:
##
## | Role | Goals | Assists | Cards |
## |------|-------|---------|-------|
## | ST   | 44%   | 12%     | 3%    |
## | LW/RW| 15%   | 18%     | 4%    |
## | CAM  | 11%   | 20%     | 7%    |
## | Pivot| 7%    | 16%     | 32%   |
## | FB   | 3%    | 12%     | 18%   |
## | CB   | 1%    | 6%      | 26%   |
## | GK   | —     | 1%      | 1%    |

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

## League averages per side: ~3.6 yellows and 0.04 reds a match in the PL.
const YELLOWS_PER_SIDE := 1.8
const RED_CHANCE := 0.04
## Share of goals that carry a recorded assist at all.
const ASSIST_CHANCE := 0.62
## Minutes are sampled across the 90 regulation minutes.
const MATCH_MINUTES := 90

## Every event for one side of one fixture: goals, assists and cards. The rows
## are plain dictionaries ready for `match_event`.
static func side(seed: int, fixture_id: String, club_id: String, xi: Array, goals: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array = []
	var used_minutes := {}
	for i in range(maxi(goals, 0)):
		var minute := _minute(rng)
		var scorer := pick(xi, GOAL_SHARE, "sho", rng)
		if scorer.is_empty():
			continue
		var row := _row(fixture_id, minute, "goal", scorer, club_id)
		var assist_row := {}
		if rng.randf() < ASSIST_CHANCE:
			var helper := pick(xi, ASSIST_SHARE, "pas", rng, str(scorer["id"]))
			if not helper.is_empty():
				# The goal row carries its assist's identity so a report clip can
				# script the final ball without pairing rows back together.
				row["assist_id"] = str(helper["id"])
				row["assist_name"] = str(helper.get("name", ""))
				assist_row = _row(fixture_id, minute, "assist", helper, club_id)
		out.append(row)
		if not assist_row.is_empty():
			out.append(assist_row)
	var yellows := clampi(int(round(YELLOWS_PER_SIDE + (rng.randf() - 0.5) * 2.0)), 0, 6)
	for i in range(yellows):
		var booked := pick(xi, CARD_SHARE, "def", rng)
		if booked.is_empty():
			continue
		var minute := _minute(rng)
		while used_minutes.has("%d/%s" % [minute, str(booked["id"])]):
			minute = _minute(rng)
		used_minutes["%d/%s" % [minute, str(booked["id"])]] = true
		out.append(_row(fixture_id, minute, "yellow", booked, club_id))
	if rng.randf() < RED_CHANCE:
		var sent_off := pick(xi, CARD_SHARE, "def", rng)
		if not sent_off.is_empty():
			out.append(_row(fixture_id, _minute(rng), "red", sent_off, club_id))
	out.sort_custom(func(a, b): return int(a["minute"]) < int(b["minute"]))
	return out

## Weighted pick over the XI. A player's share is the position prior scaled by
## the ability that role uses (finishing for goals, passing for assists, the
## defensive side for cards), so a side's best striker really does score most.
static func pick(xi: Array, shares: Dictionary, ability: String, rng: RandomNumberGenerator, skip_id: String = "") -> Dictionary:
	var weights: Array = []
	var total := 0.0
	for p in xi:
		var id := str(p.get("id", ""))
		if id == "" or id == skip_id:
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
	for i in range(weights.size()):
		acc += float(weights[i])
		if roll <= acc:
			return xi[i]
	return xi[weights.size() - 1]

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
