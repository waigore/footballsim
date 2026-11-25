class_name LeagueMonth
extends RefCounted

## The calendar's month arithmetic: `YYYY-MM` keys, stepping a month forward or
## back across a year, the label a sheet prints and the days it lays out.
##
## It was static helpers on `LeagueBook`, so the calendar's own pages and every
## caller that only needs "which month is the season in" had to reach into a
## sheet that also carries the table, the report and the podium. A month is not
## a pose: it lives on its own, and both sides read it from here.
##
## Pure and deterministic except the fallback: a missing or malformed month keys
## to the system's month, which is what a save with no clock yet shows.

const MONTHS := ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
	"AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

## "2026-08" -> [year, month]; a missing or malformed month falls back to today.
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

## The season clock's month, or the month the screen last showed when there is
## no season loaded.
static func state_month(season, fallback: String) -> String:
	if season == null:
		return fallback
	var date := str(season.state().get("date", ""))
	return date.substr(0, 7) if date.length() >= 7 else fallback

static func days_in(year: int, month: int) -> int:
	var next := key(year, month + 1)
	var stamp := Time.get_unix_time_from_datetime_string(next + "-01T00:00:00") - 86400
	return int(Time.get_datetime_dict_from_unix_time(stamp)["day"])

## The weekday column the first of the month lands in, 0 = Sunday.
static func first_weekday(month: String) -> int:
	var stamp := Time.get_unix_time_from_datetime_string(parse_key(month) + "-01T00:00:00")
	return int(Time.get_datetime_dict_from_unix_time(stamp)["weekday"])

## A month key with a safe "YYYY-MM" body even when the caller's string is not
## one: parsing it already fell back to a real month.
static func parse_key(month: String) -> String:
	var bits := parse(month)
	return key(int(bits[0]), int(bits[1]))
