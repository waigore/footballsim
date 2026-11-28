class_name MarketWindows
extends RefCounted


const PATH := "res://data/market_windows.json"

const FEE := "fee"
const FREE_AGENT := "free_agent"

const FALLBACK := {
	"associations": {
		"ENG": {"code": "FA", "name": "England"},
		"ESP": {"code": "RFEF", "name": "Spain"},
		"GER": {"code": "DFB", "name": "Germany"},
		"ITA": {"code": "FIGC", "name": "Italy"},
	},
	"defaults": [
		{"id": "summer", "open": "06-10", "close": "09-01"},
		{"id": "winter", "open": "01-01", "close": "02-02"},
	],
	"real": {},
}

static var _data: Dictionary = {}


static func reset() -> void:
	_data = {}


static func data() -> Dictionary:
	if _data.is_empty():
		_data = _read()
	return _data


static func _read() -> Dictionary:
	var text := FileAccess.get_file_as_string(PATH)
	var parsed: Variant = JSON.parse_string(text) if text != "" else null
	if parsed is Dictionary and not (parsed as Dictionary).is_empty():
		return parsed as Dictionary
	return FALLBACK.duplicate(true)


static func associations() -> Dictionary:
	return data().get("associations", {})


static func codes() -> Array:
	var out: Array = []
	for country in associations().keys():
		out.append(str(country))
	out.sort()
	return out


static func known(country: String) -> bool:
	return associations().has(country)


static func code(country: String) -> String:
	var row: Dictionary = associations().get(country, {})
	return str(row.get("code", ""))


static func name(country: String) -> String:
	var row: Dictionary = associations().get(country, {})
	return str(row.get("name", country))


static func country_of_club(club: Dictionary) -> String:
	var from_competition := LeagueTiers.country_of(str(club.get("competition_id", "")))
	if from_competition == "England":
		return "ENG"
	if from_competition == "Spain":
		return "ESP"
	if from_competition == "Germany":
		return "GER"
	if from_competition == "Italy":
		return "ITA"
	var country := str(club.get("country", ""))
	return country if known(country) else ""


static func season_label(date: String) -> String:
	if date.length() < 7:
		return ""
	var year := int(date.substr(0, 4))
	var month := int(date.substr(5, 2))
	var start := year if month >= 6 else year - 1
	return "%d-%02d" % [start, (start + 1) % 100]


static func windows(label: String, country: String) -> Array:
	if label.length() < 4 or not known(country):
		return []
	var start := int(label.substr(0, 4))
	var real: Variant = (data().get("real", {}) as Dictionary).get(country, {})
	if real is Dictionary and (real as Dictionary).has(label):
		var out: Array = []
		for row in (real as Dictionary)[label]:
			var window: Dictionary = (row as Dictionary).duplicate()
			window["season_label"] = label
			window["source"] = "real"
			window["association"] = country
			window["window_id"] = "%s-%s" % [label, str(window.get("id", ""))]
			out.append(window)
		return out
	var generated: Array = []
	for row in data().get("defaults", []):
		var window: Dictionary = (row as Dictionary).duplicate()
		var open_on := _dated(start, str(window.get("open", "")))
		var close_on := _dated(start, str(window.get("close", "")))
		if open_on.length() == 10 and int(open_on.substr(5, 2)) < 6:
			open_on = FixtureCalendar.add_years(open_on, 1)
			close_on = FixtureCalendar.add_years(close_on, 1)
		window["open"] = open_on
		window["close"] = close_on
		if str(window["close"]) < str(window["open"]):
			window["close"] = FixtureCalendar.add_years(str(window["close"]), 1)
		window["season_label"] = label
		window["source"] = "generated"
		window["association"] = country
		window["window_id"] = "%s-%s" % [label, str(window.get("id", ""))]
		generated.append(window)
	return generated


static func _dated(start_year: int, month_day: String) -> String:
	if month_day.length() != 5:
		return ""
	return "%d-%s" % [start_year, month_day]


static func open_window(date: String, country: String) -> Dictionary:
	for window in windows(season_label(date), country):
		if date >= str(window["open"]) and date <= str(window["close"]):
			return window
	return {}


static func state(date: String, country: String) -> Dictionary:
	if date == "" or not known(country):
		return {"open": false, "country": country, "code": "", "opens_on": "", "window_id": ""}
	var window := open_window(date, country)
	if not window.is_empty():
		return {
			"open": true, "country": country, "code": code(country),
			"id": str(window["id"]), "window_id": str(window["window_id"]),
			"opens_on": str(window["open"]), "closes_on": str(window["close"]),
			"season_label": str(window["season_label"]), "source": str(window["source"]),
		}
	var next := _next_window(date, country)
	return {
		"open": false, "country": country, "code": code(country),
		"id": str(next.get("id", "")), "window_id": "",
		"opens_on": str(next.get("open", "")), "closes_on": str(next.get("close", "")),
		"season_label": str(next.get("season_label", season_label(date))),
		"source": str(next.get("source", "")),
	}


static func _next_window(date: String, country: String) -> Dictionary:
	var label := season_label(date)
	var candidates: Array = windows(label, country) + windows(_next_label(label), country)
	for window in candidates:
		if str(window["open"]) > date:
			return window
	return {}


static func _next_label(label: String) -> String:
	if label.length() < 4:
		return ""
	var start := int(label.substr(0, 4)) + 1
	return "%d-%02d" % [start, (start + 1) % 100]


static func board(date: String) -> Array:
	var out: Array = []
	for country in codes():
		out.append(state(date, country))
	return out


static func allows(kind: String, date: String, buyer_country: String, seller_country: String) -> Dictionary:
	var mine := state(date, buyer_country)
	if kind == FREE_AGENT:
		return {
			"ok": true, "reason": "free_agent", "window_id": str(mine.get("window_id", "")),
			"buyer": buyer_country, "seller": seller_country,
		}
	if bool(mine.get("open", false)):
		return {
			"ok": true, "reason": "open", "window_id": str(mine.get("window_id", "")),
			"buyer": buyer_country, "seller": seller_country,
		}
	return {
		"ok": false, "reason": "window_closed", "window_id": "",
		"buyer": buyer_country, "seller": seller_country,
		"opens_on": str(mine.get("opens_on", "")),
	}


static func is_participant(club: Dictionary) -> bool:
	if club.is_empty() or int(club.get("stub", 0)) == 1:
		return false
	return country_of_club(club) != ""
