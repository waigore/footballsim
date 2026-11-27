class_name MatchKicking
extends RefCounted


const NEUTRAL := 64.75


const REACH_PER_POINT := 0.45


const SCATTER_PER_POINT := 0.16
const SCATTER_CAP := 8.0


static func kick_of(bars: Dictionary) -> float:
	return clampf(float(bars.get("kic", NEUTRAL)), 0.0, 100.0)


static func aim_point(bars: Dictionary, from: Vector2, aim: Vector2) -> Vector2:
	var d: float = from.distance_to(aim)
	if d < 0.5:
		return aim
	var travel: float = maxf(9.0, d + (kick_of(bars) - NEUTRAL) * REACH_PER_POINT)
	return from + (aim - from) / d * travel


static func scatter(bars: Dictionary) -> float:
	return clampf((NEUTRAL - kick_of(bars)) * SCATTER_PER_POINT, 0.0, SCATTER_CAP)


static func landing(bars: Dictionary, from: Vector2, aim: Vector2, side: float, depth: float) -> Vector2:
	return aim_point(bars, from, aim) + Vector2(side, depth) * scatter(bars)
