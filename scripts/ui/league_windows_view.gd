class_name LeagueWindowsView
extends RefCounted


const CHIP_H := 20.0
const CHIP_GAP := 4.0
const WIDE_X := 760.0


static func rows(date: String) -> Array:
	if date == "":
		return []
	return MarketWindows.board(date)


static func chip_text(row: Dictionary) -> String:
	var code := MarketWindows.code(str(row.get("country", "")))
	if bool(row.get("open", false)):
		return "%s DEAL TODAY" % code
	var opens := FixtureCalendar.day_label(str(row.get("opens_on", "")))
	if opens == "":
		return "%s NO DEAL" % code
	return "%s NO DEAL · OPENS %s" % [code, opens]


static func cols(vp: Vector2) -> int:
	return 4 if vp.x >= WIDE_X else 2
