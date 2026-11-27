class_name ChromeDensity
extends RefCounted


const BASE := 1.25

const REF_H := 900.0


const MAX := 1.6


static func scale_for(points: Vector2) -> float:
	return clampf(BASE * maxf(points.y, REF_H) / REF_H, BASE, MAX)


const MIN_READ := 10


static func read_size(size: int) -> int:
	return maxi(size, MIN_READ)


static func window_points() -> Vector2:
	var px := Vector2(DisplayServer.window_get_size())
	if px.x <= 0.0 or px.y <= 0.0:
		return Vector2(REF_H * 16.0 / 9.0, REF_H)
	return px / maxf(DisplayServer.screen_get_scale(), 1.0)


static func non_match_scale() -> float:
	return scale_for(window_points())
