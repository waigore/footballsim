class_name MarketValuation
extends RefCounted


const FAMILY := {
	"GK": "GK",
	"RB": "FB", "LB": "FB",
	"RCB": "CB", "LCB": "CB", "CB": "CB",
	"RDM": "PIVOT", "LDM": "PIVOT", "CDM": "PIVOT", "CM": "PIVOT",
	"RW": "WING", "LW": "WING", "RM": "WING", "LM": "WING",
	"CAM": "CAM", "ST": "ST",
}


static func band_value(ovr: int) -> int:
	for band in MarketRules.section("valuation").get("bands", []):
		if ovr >= int((band as Dictionary).get("min_ovr", 0)):
			return int((band as Dictionary).get("value", 0))
	return 0


static func age_mult(age: int) -> float:
	for band in MarketRules.section("valuation").get("age", []):
		if age <= int((band as Dictionary).get("max", 200)):
			return float((band as Dictionary).get("mult", 1.0))
	return 1.0


static func contract_mult(years: int) -> float:
	var span := maxi(years, 0)
	for band in MarketRules.section("valuation").get("contract", []):
		if span >= int((band as Dictionary).get("min", 0)):
			return float((band as Dictionary).get("mult", 1.0))
	return 1.0


static func position_mult(pos: String) -> float:
	var table: Dictionary = MarketRules.section("valuation").get("position", {})
	var found: Variant = table.get(pos, null)
	if found is float or found is int:
		return float(found)
	return float(table.get("default", 1.0))


static func form_mult(stats: Dictionary, pos: String) -> float:
	var spec: Dictionary = MarketRules.section("valuation").get("form", {})
	var matches := int(stats.get("matches", 0))
	if matches <= 0:
		return 1.0
	var contributions := float(int(stats.get("goals", 0)) + int(stats.get("assists", 0)))
	var actual := contributions / float(matches)
	var expected := float((spec.get("expected", {}) as Dictionary).get(
		str(FAMILY.get(pos, pos)), 0.0))
	var factor := 1.0 + float(spec.get("weight", 0.3)) * (actual - expected)
	return clampf(factor, float(spec.get("floor", 0.9)), float(spec.get("ceiling", 1.15)))


static func years_left(contract: Dictionary, date: String) -> int:
	var end := str(contract.get("end_date", ""))
	if end == "" or date == "":
		return 0
	var days := FixtureCalendar.days_from(end) - FixtureCalendar.days_from(date)
	if days <= 0:
		return 0
	return int(ceil(float(days) / 365.25))


static func value(player: Dictionary, contract: Dictionary, date: String = "") -> int:
	var ovr := int(player.get("ovr", 0))
	var base := band_value(ovr)
	if base <= 0:
		return 0
	var pos := str(player.get("pos", player.get("role", "")))
	var mult := age_mult(int(player.get("age", 0)))
	mult *= contract_mult(years_left(contract, date))
	mult *= position_mult(pos)
	mult *= form_mult(player.get("season", {}), pos)
	return int(round(float(base) * mult))


static func weekly_wage(value_amount: int, current_wage: int) -> int:
	var spec := MarketRules.section("valuation")
	var step := maxi(MarketRules.count("valuation", "wage_step", 10), 1)
	var per_million := float(spec.get("wage_per_million", 2200))
	var millions := float(value_amount) / 1_000_000.0
	var wage := int(round(millions * per_million / float(step))) * step
	var floor := int(ceil(float(current_wage) * float(spec.get("wage_uplift", 1.05))
		/ float(step))) * step
	return maxi(maxi(wage, floor), step)
