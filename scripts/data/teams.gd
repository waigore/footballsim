class_name TeamData
extends RefCounted

## Squads, clubs and the league table come from the cached SQLite snapshot
## (`data/pl_seed.sqlite`, built by `tools/pl_snapshot.py`). This facade keeps
## the small API the engine, picker and tests already speak, so the storage swap
## stays invisible above it. Formation geometry is code, not data, and lives
## here.

## Named match official. One source for the broadcast chrome and the pitch
## official: a referee name change belongs here, not in the HUD.
const REFEREE := "M. OLIVER"

const FIXTURE := {
	"home": "MUN",
	"away": "MCI",
	"stadium": "OLD TRAFFORD",
	"city": "MANCHESTER",
	"competition": "PREMIER LEAGUE",
	"attendance": 74197,
	"kickoff": "20:00",
}

## Live formations for the FM-style tactics board. Every shape lists all eleven
## canonical squad roles so a mid-match change re-slots the same XI instead of
## inventing players; bench roles fall back in `formation_slot`.
const CANONICAL_ROLES := ["GK", "RB", "RCB", "LCB", "LB", "RDM", "LDM", "RW", "CAM", "LW", "ST"]

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
	"4-4-2": {
		"GK": Vector2(0.035, 0.50),
		"RB": Vector2(0.24, 0.86),
		"RCB": Vector2(0.155, 0.61),
		"LCB": Vector2(0.155, 0.39),
		"LB": Vector2(0.24, 0.14),
		"RW": Vector2(0.52, 0.88),
		"RDM": Vector2(0.38, 0.58),
		"LDM": Vector2(0.38, 0.42),
		"LW": Vector2(0.52, 0.12),
		"CAM": Vector2(0.70, 0.36),
		"ST": Vector2(0.70, 0.64),
	},
	"4-3-3": {
		"GK": Vector2(0.035, 0.50),
		"RB": Vector2(0.24, 0.86),
		"RCB": Vector2(0.155, 0.61),
		"LCB": Vector2(0.155, 0.39),
		"LB": Vector2(0.24, 0.14),
		"RDM": Vector2(0.33, 0.58),
		"LDM": Vector2(0.33, 0.42),
		"CAM": Vector2(0.52, 0.50),
		"RW": Vector2(0.66, 0.87),
		"LW": Vector2(0.66, 0.13),
		"ST": Vector2(0.73, 0.50),
	},
	"3-5-2": {
		"GK": Vector2(0.035, 0.50),
		"RCB": Vector2(0.16, 0.64),
		"LCB": Vector2(0.16, 0.36),
		"RB": Vector2(0.38, 0.90),
		"LB": Vector2(0.38, 0.10),
		"RDM": Vector2(0.34, 0.55),
		"LDM": Vector2(0.34, 0.45),
		"CAM": Vector2(0.54, 0.50),
		"RW": Vector2(0.64, 0.80),
		"LW": Vector2(0.64, 0.20),
		"ST": Vector2(0.75, 0.50),
	},
	"5-3-2": {
		"GK": Vector2(0.035, 0.50),
		"RB": Vector2(0.22, 0.88),
		"RCB": Vector2(0.15, 0.66),
		"RDM": Vector2(0.17, 0.50),
		"LCB": Vector2(0.15, 0.34),
		"LB": Vector2(0.22, 0.12),
		"LDM": Vector2(0.38, 0.50),
		"CAM": Vector2(0.55, 0.50),
		"RW": Vector2(0.62, 0.85),
		"LW": Vector2(0.62, 0.15),
		"ST": Vector2(0.75, 0.50),
	},
	"4-1-4-1": {
		"GK": Vector2(0.035, 0.50),
		"RB": Vector2(0.24, 0.86),
		"RCB": Vector2(0.155, 0.61),
		"LCB": Vector2(0.155, 0.39),
		"LB": Vector2(0.24, 0.14),
		"RDM": Vector2(0.30, 0.50),
		"LDM": Vector2(0.45, 0.58),
		"CAM": Vector2(0.45, 0.42),
		"RW": Vector2(0.62, 0.86),
		"LW": Vector2(0.62, 0.14),
		"ST": Vector2(0.74, 0.50),
	},
}

static func team_ids() -> Array:
	return PLRepository.shared().club_ids()

static func get_team(id: String) -> Dictionary:
	return PLRepository.shared().team(id)

static func other(id: String) -> String:
	return "MCI" if id == "MUN" else "MUN"

static func slots(formation: String) -> Dictionary:
	return FORMATIONS.get(formation, FORMATIONS["4-2-3-1"])

static func formation_slot(team: Dictionary, role: String) -> Vector2:
	return formation_slot_for(str(team.get("formation", "4-2-3-1")), role)

## Slot for a role in a named formation. Bench players brought on out of
## position fall back to a sensible line.
static func formation_slot_for(formation: String, role: String) -> Vector2:
	var f: Dictionary = slots(formation)
	if f.has(role):
		return f[role]
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
