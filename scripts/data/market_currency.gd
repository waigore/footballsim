class_name MarketCurrency
extends RefCounted


static func rates() -> Dictionary:
	var found: Variant = MarketRules.section("currency").get("rates", {})
	return found if found is Dictionary else {}


static func symbols() -> Dictionary:
	var found: Variant = MarketRules.section("currency").get("symbols", {})
	return found if found is Dictionary else {}


static func currencies() -> Array:
	var out: Array = []
	for key in rates().keys():
		out.append(str(key))
	out.sort()
	return out


static func default_code() -> String:
	return str(MarketRules.section("currency").get("default", "GBP"))


static func code_of(currency: String = "") -> String:
	var wanted := currency if currency != "" else Prefs.load_currency()
	return wanted if currencies().has(wanted) else default_code()


static func symbol(currency: String = "") -> String:
	var code := code_of(currency)
	return str(symbols().get(code, code + " "))


static func rate(currency: String = "") -> float:
	return float(rates().get(code_of(currency), 1.0))


static func shown(amount: int, currency: String = "") -> float:
	return float(amount) * rate(currency)


static func to_base(entered: int, currency: String = "") -> int:
	return int(round(float(entered) / maxf(rate(currency), 0.0001)))


static func format(amount: int, currency: String = "") -> String:
	var mark := symbol(currency)
	var value := shown(amount, currency)
	var sign := "-" if value < 0.0 else ""
	var size := absf(value)
	if size >= 1000000.0:
		return "%s%s%.1fM" % [sign, mark, size / 1000000.0]
	if size >= 1000.0:
		return "%s%s%dK" % [sign, mark, int(round(size / 1000.0))]
	return "%s%s%d" % [sign, mark, int(round(size))]


static func format_units(amount: int, currency: String = "") -> String:
	var mark := symbol(currency)
	var value := int(round(shown(amount, currency)))
	var sign := "-" if value < 0 else ""
	var digits := str(absi(value))
	var out := ""
	var count := 0
	for i in range(digits.length() - 1, -1, -1):
		out = digits.substr(i, 1) + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return sign + mark + out
