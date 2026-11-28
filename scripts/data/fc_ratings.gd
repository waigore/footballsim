class_name FCRatings
extends RefCounted


const MODEL_PATH := "res://data/fc_ratings.json"
const MAX := 99

static var _model: Dictionary = {}


static func model() -> Dictionary:
	if not _model.is_empty():
		return _model
	var text := FileAccess.get_file_as_string(MODEL_PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	_model = parsed if parsed is Dictionary else {}
	return _model


static func sub_stat_keys() -> Array:
	return model().get("sub_stats", [])


static func half_up(value: float) -> int:
	return int(floor(value + 0.5))


static func weighted(sub: Dictionary, weights: Dictionary) -> int:
	var total := 0
	for key in weights:
		total += int(sub.get(key, 0)) * int(weights[key])
	return half_up(float(total) / 100.0)


static func face_stats(sub: Dictionary) -> Dictionary:
	var out := {}
	var table: Dictionary = model().get("face", {})
	for name in table:
		out[str(name)] = weighted(sub, table[name])
	return out


static func keeper_stats(sub: Dictionary) -> Dictionary:
	var out := {}
	for pair in model().get("keeper_face", []):
		out[str(pair[0])] = int(sub.get(str(pair[1]), 30))
	var speed := str(model().get("keeper_speed", "pace"))
	out["spd"] = weighted(sub, (model().get("face", {}) as Dictionary).get(speed, {}))
	return out


static func position_for(role: String) -> String:
	var table: Dictionary = model().get("role_position", {})
	return str(table.get(role, "CM"))


static func overall(sub: Dictionary, role: String, intl_rep: int = 1) -> int:
	var book := model()
	var position := position_for(role)
	var spec: Dictionary = (book.get("positions", {}) as Dictionary).get(position, {})
	if spec.is_empty():
		spec = (book.get("positions", {}) as Dictionary).get("CM", {})
	var value := float(weighted(sub, spec.get("weights", {}))) + float(spec.get("slot_bias", 0.0))
	var rule: Dictionary = book.get("intl_rep", {})
	if intl_rep >= int(rule.get("from", 4)):
		value += float(rule.get("bonus", 0))
	return clampi(half_up(value), 1, MAX)


static func card(sub: Dictionary, role: String, intl_rep: int = 1) -> Dictionary:
	return {
		"ovr": overall(sub, role, intl_rep),
		"face": face_stats(sub),
		"gk": keeper_stats(sub),
	}


static func clamped(sub: Dictionary) -> Dictionary:
	var out := {}
	for key in sub:
		out[str(key)] = clampi(int(sub[key]), 1, MAX)
	return out


static func synthesize(club_base: float, role: String, wobble: int = 0) -> Dictionary:
	var book := model()
	var table: Dictionary = book.get("synthesis", {})
	var profile: Dictionary = (table.get("roles", {}) as Dictionary).get(position_for(role), {})
	if profile.is_empty():
		profile = (table.get("roles", {}) as Dictionary).get("CM", {})
	var delta: float = club_base - float(table.get("base", 70))
	var out := {}
	for key in profile:
		out[str(key)] = int(round(float(profile[key]) + delta + float(wobble)))
	return clamped(out)


static func height_ok(value: int) -> bool:
	return value >= 160 and value <= 210
