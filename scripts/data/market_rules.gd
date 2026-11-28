class_name MarketRules
extends RefCounted


const PATH := "res://data/market_rules.json"

static var _rules: Dictionary = {}


static func rules() -> Dictionary:
	if not _rules.is_empty():
		return _rules
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	_rules = parsed if parsed is Dictionary else {}
	return _rules


static func section(name: String) -> Dictionary:
	var found: Variant = rules().get(name, {})
	return found if found is Dictionary else {}


static func number(name: String, key: String, fallback: float) -> float:
	var value: Variant = section(name).get(key, fallback)
	if value is float or value is int:
		return float(value)
	return fallback


static func count(name: String, key: String, fallback: int) -> int:
	return int(round(number(name, key, float(fallback))))


static func ticket_price(competition_id: String) -> int:
	var prices := section("revenue").get("ticket_price", {})
	var value: Variant = (prices as Dictionary).get(competition_id, null) if prices is Dictionary else null
	if value is float or value is int:
		return int(value)
	return count("revenue", "default_ticket_price", 14)


static func revenue_multiplier(competition_id: String) -> float:
	var table := section("revenue").get("multiplier", {})
	var value: Variant = (table as Dictionary).get(competition_id, null) if table is Dictionary else null
	if value is float or value is int:
		return float(value)
	return number("revenue", "default_multiplier", 1.0)
