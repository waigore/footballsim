class_name TeamData
extends RefCounted

## Squad data lives in shards (teams_core / teams_pl1..3) so each file stays
## under the architecture hard ceiling. Add a club to the matching shard.
## MUN and MCI use OVRBase FC 26 club ratings (retrieved Nov 2026); the other
## 18 use real 2025-26 squads with ratings estimated from role and overall.

const _SHARDS := [
	preload("res://scripts/data/teams_core.gd"),
	preload("res://scripts/data/teams_pl1.gd"),
	preload("res://scripts/data/teams_pl2.gd"),
	preload("res://scripts/data/teams_pl3.gd"),
]

const FIXTURE := {
	"home": "MUN",
	"away": "MCI",
	"stadium": "OLD TRAFFORD",
	"city": "MANCHESTER",
	"competition": "PREMIER LEAGUE",
	"attendance": 74197,
	"referee": "M. OLIVER",
	"kickoff": "20:00",
}

const FORMATIONS := {
	"4-2-3-1": {
		"GK": Vector2(0.035, 0.50),
		"RB": Vector2(0.24, 0.86),
		"RCB": Vector2(0.155, 0.61),
		"LCB": Vector2(0.155, 0.39),
		"LB": Vector2(0.24, 0.14),
		"RDM": Vector2(0.33, 0.58),
		"LDM": Vector2(0.33, 0.42),
		"RW": Vector2(0.60, 0.87),
		"CAM": Vector2(0.545, 0.50),
		"LW": Vector2(0.60, 0.13),
		"ST": Vector2(0.715, 0.50),
	},
}

static var _cache: Dictionary = {}

static func _squads() -> Dictionary:
	if _cache.is_empty():
		for shard in _SHARDS:
			_cache.merge(shard.TEAMS)
	return _cache

static func team_ids() -> Array:
	return _squads().keys()

static func get_team(id: String) -> Dictionary:
	return _squads()[id]

static func other(id: String) -> String:
	return "MCI" if id == "MUN" else "MUN"

static func formation_slot(team: Dictionary, role: String) -> Vector2:
	var f: Dictionary = FORMATIONS[team["formation"]]
	if f.has(role):
		return f[role]
	# Fallbacks for bench players brought on out of position.
	match role:
		"CB": return Vector2(0.155, 0.5)
		"CDM": return Vector2(0.33, 0.5)
		"CM": return Vector2(0.36, 0.5)
		"LM", "RM": return Vector2(0.6, 0.5)
		"LW", "RW": return Vector2(0.6, 0.2)
		"CAM": return Vector2(0.55, 0.5)
		"ST": return Vector2(0.715, 0.5)
		"GK": return Vector2(0.035, 0.5)
	return Vector2(0.3, 0.5)
