class_name LeagueMonth
extends RefCounted


const MONTHS := ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
	"AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]


static func parse(month: String) -> Array:
	if month.length() == 7 and month.substr(4, 1) == "-":
		return [int(month.substr(0, 4)), int(month.substr(5, 2))]
	var now := Time.get_date_dict_from_system()
	return [int(now["year"]), int(now["month"])]

static func key(year: int, month: int) -> String:
	var m := ((month - 1) % 12 + 12) % 12 + 1
	var y := year + int(floor(float(month - 1) / 12.0))
	return "%04d-%02d" % [y, m]

static func shift(month: String, delta: int) -> String:
	var bits := parse(month)
	return key(int(bits[0]), int(bits[1]) + delta)

static func label(month: String) -> String:
	var bits := parse(month)
	return "%s %d" % [MONTHS[int(bits[1]) - 1], int(bits[0])]

static func days(month: String) -> int:
	var bits := parse(month)
	return days_in(int(bits[0]), int(bits[1]))


static func state_month(season, fallback: String) -> String:
	if season == null:
		return fallback
	var date := str(season.state().get("date", ""))
	return date.substr(0, 7) if date.length() >= 7 else fallback

static func days_in(year: int, month: int) -> int:
	var next := key(year, month + 1)
	var stamp := Time.get_unix_time_from_datetime_string(next + "-01T00:00:00") - 86400
	return int(Time.get_datetime_dict_from_unix_time(stamp)["day"])


static func first_weekday(month: String) -> int:
	var stamp := Time.get_unix_time_from_datetime_string(parse_key(month) + "-01T00:00:00")
	return int(Time.get_datetime_dict_from_unix_time(stamp)["weekday"])


static func parse_key(month: String) -> String:
	var bits := parse(month)
	return key(int(bits[0]), int(bits[1]))
