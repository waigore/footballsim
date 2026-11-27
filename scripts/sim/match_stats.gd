class_name MatchStats
extends RefCounted


const FRAME_R := 0.17


const INTERCEPTION_WINDOW := 3.0


const INTERCEPTION_SPEED := 6.0


const MOMENTUM_HALF_LIFE := 90.0


const MOMENTUM_SCALE := 0.12


const WOODWORK_P := 0.18


const MOMENTUM_WEIGHT := {
	"goal": 0.60,
	"save": 0.16,
	"block": 0.10,
	"shot": 0.12,
	"header": 0.12,
	"cross": 0.03,
	"corner": 0.05,
}


const MOMENTUM_INVERTED := ["save", "block"]


static func goal_plane_point(pos: Vector2, vel: Vector2, z: float, vz: float,
		line_x: float) -> Vector2:
	var vx: float = absf(vel.x)
	if vx < 0.001:
		return Vector2(pos.y, z)
	var back: float = clampf(absf(pos.x - line_x) / vx, 0.0, 0.05)
	return Vector2(pos.y - vel.y * back, z - vz * back)


static func frame_hit(goal_y: float, goal_w: float, goal_h: float, y: float,
		z: float) -> String:
	var dy: float = absf(y - goal_y)
	if absf(dy - goal_w * 0.5) <= FRAME_R and z <= goal_h + FRAME_R:
		return "post"
	if absf(z - goal_h) <= FRAME_R and dy <= goal_w * 0.5 + FRAME_R:
		return "bar"
	return ""


static func decay(dt: float) -> float:
	return pow(0.5, maxf(dt, 0.0) / MOMENTUM_HALF_LIFE)


static func bump(pressure: Array, team: int, kind: String, xg: float = 0.0) -> void:
	if team < 0 or team > 1 or pressure.size() < 2:
		return
	var w: float = float(MOMENTUM_WEIGHT.get(kind, 0.0))
	if w <= 0.0:
		return
	if kind in MOMENTUM_INVERTED:
		team = 1 - team
	if kind in ["shot", "header"]:
		w *= 0.5 + clampf(xg, 0.0, 0.8)
	pressure[team] = float(pressure[team]) + w


static func momentum_level(pressure: Array) -> Vector2:
	if pressure.size() < 2:
		return Vector2.ZERO
	var home: float = 1.0 - exp(-maxf(float(pressure[0]), 0.0) / MOMENTUM_SCALE)
	var away: float = 1.0 - exp(-maxf(float(pressure[1]), 0.0) / MOMENTUM_SCALE)
	return Vector2(snappedf(home, 0.01), snappedf(away, 0.01))


const MOMENTUM_ON_TOP := 0.66
const MOMENTUM_PRESSING := 0.28

const MOMENTUM_CLEAR_GAP := 0.08


static func momentum_leader(levels: Vector2) -> int:
	var gap: float = absf(levels.x - levels.y)
	if gap < MOMENTUM_CLEAR_GAP:
		return -1
	return 0 if levels.x > levels.y else 1


static func momentum_phrase(level: float) -> String:
	if level >= MOMENTUM_ON_TOP:
		return "ON TOP"
	if level >= MOMENTUM_PRESSING:
		return "PRESSING"
	return ""
