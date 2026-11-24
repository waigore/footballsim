class_name Attrs
extends RefCounted

## Translates EA FC 26 0-100 attributes into simulation quantities.
## Every mapping here is deliberately readable: one place to tune the whole game.

const PITCH_L := 105.0
const PITCH_W := 68.0
const GOAL_W := 7.32
const GOAL_H := 2.44

static func max_speed(p) -> float:
	# Elite sprint ~8.9 m/s, slowest outfielders ~5.6 m/s.
	var pac: float = float(p.attr["pac"])
	return 5.0 + pow(pac / 100.0, 2.0) * 4.0

static func accel(p) -> float:
	var pac: float = float(p.attr["pac"])
	return 3.0 + (pac / 100.0) * 3.4

static func decel(p) -> float:
	return 6.5 + float(p.attr["phy"]) * 0.02

static func dribble_speed(p) -> float:
	var dri: float = float(p.attr["dri"])
	return max_speed(p) * (0.78 + dri / 100.0 * 0.16)

static func control_radius(p) -> float:
	# How far a player can pluck a loose ball from.
	var dri: float = float(p.attr["dri"])
	return 1.18 + dri * 0.0052

static func first_touch_quality(p) -> float:
	return 0.45 + float(p.attr["dri"]) / 100.0 * 0.55

static func pass_sigma_deg(p, dist: float, pressure: float) -> float:
	var pas: float = float(p.attr["pas"])
	return 1.05 + (100.0 - pas) * 0.085 + dist * 0.032 + pressure * 2.6

static func pass_speed_for(p, dist: float) -> float:
	# A pass arrives with enough pace to beat a defender but be controllable.
	var pas: float = float(p.attr["pas"])
	var base := clampf(6.2 + dist * 0.33, 8.0, 19.5)
	return base * (0.94 + pas * 0.0008)

static func shot_sigma_deg(p, dist: float, pressure: float) -> float:
	var sho: float = float(p.attr["sho"])
	return 5.5 + (100.0 - sho) * 0.170 + dist * 0.085 + pressure * 9.2

static func shot_speed(p, power: float = 1.0) -> float:
	var sho: float = float(p.attr["sho"])
	return (18.0 + sho * 0.14) * power

static func tackle_skill(p) -> float:
	return float(p.attr["def"]) / 100.0

static func strength(p) -> float:
	return 0.35 + float(p.attr["phy"]) / 100.0 * 0.65

static func aerial(p) -> float:
	# Height and physicality, 0..1.
	var h: float = float(p.attr.get("height", 180))
	var phy: float = float(p.attr["phy"])
	return clampf((h - 160.0) / 45.0 * 0.55 + phy / 100.0 * 0.45, 0.0, 1.0)

static func stamina_drain(p, speed: float, dt: float) -> float:
	var phy: float = float(p.attr["phy"])
	var intensity: float = clampf(speed / max(1.0, max_speed(p)), 0.0, 1.0)
	var per_sec: float = 0.00055 + intensity * intensity * 0.0026
	return per_sec * dt * (1.25 - phy / 100.0 * 0.45)

static func gk_reach(p) -> float:
	var ref: float = float(p.gk["ref"])
	return 0.95 + ref * 0.0105  # metres from body, plus dive extension below

static func gk_reaction(p) -> float:
	var ref: float = float(p.gk["ref"])
	return maxf(0.10, 0.34 - ref * 0.0024)

static func gk_dive_reach(p) -> float:
	var div: float = float(p.gk["div"])
	return 0.85 + div * 0.0115

static func gk_handling(p) -> float:
	return float(p.gk["han"]) / 100.0

## --- role helpers -----------------------------------------------------------

static func is_defender(role: String) -> bool:
	return role in ["RB", "LB", "CB", "RCB", "LCB", "RWB", "LWB"]

static func is_mid(role: String) -> bool:
	return role in ["CDM", "RDM", "LDM", "CM", "RM", "LM", "CAM"]

static func is_forward(role: String) -> bool:
	return role in ["RW", "LW", "ST", "CF"]

static func is_wide(role: String) -> bool:
	return role in ["RB", "LB", "RWB", "LWB", "RW", "LW", "RM", "LM"]

static func is_gk(role: String) -> bool:
	return role == "GK"

## Attacking x-position weight used by the AI when choosing passes.
## Block bodies (not `"ST": return 1.0`) keep every arm on its own line so the
## coverage injector can place a tracker inside the arm.
static func role_push(role: String) -> float:
	match role:
		"ST":
			return 1.0
		"RW", "LW":
			return 0.8
		"CAM":
			return 0.7
		"CM", "RDM", "LDM", "CDM":
			return 0.35
		"RB", "LB":
			return 0.3
		"CB", "RCB", "LCB":
			return 0.05
	return 0.3
