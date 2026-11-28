class_name Kits
extends RefCounted


const WHITE := Color("#f4f4f2")
const BLACK := Color("#141a1f")
const CHANGE_YELLOW := Color("#f2d24b")


static func assign(teams: Array) -> void:
	var home: Dictionary = teams[0]["data"]
	var away: Dictionary = teams[1]["data"]
	var home_kit := _primary(home)
	var away_kit := _primary(away)
	if clash(home_kit["shirt"], away_kit["shirt"]):
		away_kit = _change_kit(away, home_kit["shirt"])
	teams[0]["kit"] = home_kit
	teams[1]["kit"] = away_kit


static func _primary(data: Dictionary) -> Dictionary:
	var shirt: Color = data.get("color", WHITE)
	var shorts: Color = data.get("shorts", WHITE)
	return {"shirt": shirt, "shorts": shorts}


static func clash(a: Color, b: Color) -> bool:
	var la: float = a.get_luminance()
	var lb: float = b.get_luminance()
	if absf(la - lb) >= 0.22:
		return false
	var dh: float = absf(a.h - b.h)
	dh = minf(dh, 1.0 - dh)
	if a.s < 0.16 and b.s < 0.16:
		return absf(la - lb) < 0.12
	return dh < 0.10 and a.s > 0.25 and b.s > 0.25


static func _change_kit(data: Dictionary, avoid: Color) -> Dictionary:
	var primary: Color = data.get("color", WHITE)
	var shorts: Color = data.get("shorts", WHITE)
	var dark: Color = data.get("color_dark", BLACK)
	var light: Color = data.get("color_light", WHITE)
	var cands := [
		{"shirt": shorts, "shorts": primary},
		{"shirt": light.lightened(0.25), "shorts": dark},
		{"shirt": WHITE, "shorts": dark},
		{"shirt": CHANGE_YELLOW, "shorts": dark},
		{"shirt": BLACK, "shorts": WHITE},
	]
	for c in cands:
		if not clash(c["shirt"], avoid):
			return c
	return {"shirt": CHANGE_YELLOW, "shorts": dark}


static func ink(shirt: Color) -> Color:
	return Color(0.08, 0.12, 0.16, 0.96) if shirt.get_luminance() > 0.55 else Color(1, 1, 1, 0.96)
