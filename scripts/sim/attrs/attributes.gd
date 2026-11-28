class_name Attrs
extends RefCounted


const PITCH_L := 105.0
const PITCH_W := 68.0
const GOAL_W := 7.32
const GOAL_H := 2.44


static func max_speed(p: Variant) -> float:
	var pac: float = float(p.attr["pac"])
	return 5.0 + pow(pac / 100.0, 2.0) * 4.0


static func accel(p: Variant) -> float:
	var pac: float = float(p.attr["pac"])
	return 3.0 + (pac / 100.0) * 3.4


static func decel(p: Variant) -> float:
	return 6.5 + float(p.attr["phy"]) * 0.02


static func dribble_speed(p: Variant) -> float:
	var dri: float = float(p.attr["dri"])
	return max_speed(p) * (0.78 + dri / 100.0 * 0.16)


static func control_radius(p: Variant) -> float:
	var dri: float = float(p.attr["dri"])
	return 1.18 + dri * 0.0052


static func first_touch_quality(p: Variant) -> float:
	return 0.45 + float(p.attr["dri"]) / 100.0 * 0.55


static func pass_sigma_deg(p: Variant, dist: float, pressure: float) -> float:
	var pas: float = float(p.attr["pas"])
	return 1.05 + (100.0 - pas) * 0.085 + dist * 0.032 + pressure * 2.6


static func pass_speed_for(p: Variant, dist: float) -> float:
	var pas: float = float(p.attr["pas"])
	var base := clampf(6.2 + dist * 0.33, 8.0, 19.5)
	return base * (0.94 + pas * 0.0008)


static func shot_sigma_deg(p: Variant, dist: float, pressure: float) -> float:
	var sho: float = float(p.attr["sho"])
	return 5.5 + (100.0 - sho) * 0.170 + dist * 0.085 + pressure * 9.2


static func shot_speed(p: Variant, power: float = 1.0) -> float:
	var sho: float = float(p.attr["sho"])
	return (18.0 + sho * 0.14) * power


static func tackle_skill(p: Variant) -> float:
	return float(p.attr["def"]) / 100.0


static func strength(p: Variant) -> float:
	return 0.35 + float(p.attr["phy"]) / 100.0 * 0.65


static func aerial(p: Variant) -> float:
	var h: float = float(p.attr.get("height", 180))
	var phy: float = float(p.attr["phy"])
	return clampf((h - 160.0) / 45.0 * 0.55 + phy / 100.0 * 0.45, 0.0, 1.0)


static func stamina_drain(p: Variant, speed: float, dt: float) -> float:
	var phy: float = float(p.attr["phy"])
	var intensity: float = clampf(speed / max(1.0, max_speed(p)), 0.0, 1.0)
	var per_sec: float = 0.00055 + intensity * intensity * 0.0026
	return per_sec * dt * (1.25 - phy / 100.0 * 0.45)
