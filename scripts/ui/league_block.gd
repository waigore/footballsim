class_name LeagueBlock
extends RefCounted


const BASE := 36.0

const LINE := 15.0
const TIGHT_BASE := 32.0
const TIGHT_LINE := 14.0
const GUTTER := 16.0
const INSET := 10.0


static func columns(rect: Rect2) -> Dictionary:
	var mid := rect.position.x + rect.size.x * 0.5 + GUTTER * 0.5
	return {
		"home_x": rect.position.x + INSET,
		"away_x": mid,
		"home_w": maxf(rect.size.x * 0.5 - INSET - GUTTER, 60.0),
		"away_w": maxf(rect.end.x - mid - INSET, 60.0),
	}


static func report_of(fixture: Dictionary) -> Dictionary:
	return {"fixture": fixture, "events": fixture.get("events", [])}


static func height(fixture: Dictionary, tight: bool = false) -> float:
	if str(fixture.get("status", "")) != "played":
		return 0.0
	var sides := LeagueRoundup.sides(report_of(fixture))
	var rows := maxi((sides["home"] as Array).size(), (sides["away"] as Array).size())
	return (TIGHT_BASE if tight else BASE) + float(rows) * (TIGHT_LINE if tight else LINE)


static func paint(c: CanvasItem, rect: Rect2, fixture: Dictionary, fonts: Dictionary,
		names: InterestNames, home_ink: Color, away_ink: Color, tight: bool = false) -> void:
	var bold: Font = fonts["bold"]
	var name_size := 11 if tight else 13
	var line_h := TIGHT_LINE if tight else LINE
	var head := TIGHT_BASE if tight else BASE
	var places := columns(rect)
	var played := str(fixture.get("status", "")) == "played"
	var kick := str(fixture.get("kickoff_time", ""))


	UiChrome.text(c, Vector2(rect.position.x + 8.0, rect.position.y + 15.0),
		"FT" if played else kick, 10, UiChrome.C_GOLD if played else UiChrome.C_DIM, bold)
	var score := "%d  –  %d" % [int(fixture.get("home_goals", 0)), int(fixture.get("away_goals", 0))]
	UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + (15.0 if tight else 16.0), score,
		12 if tight else 13, UiChrome.C_TEXT, bold)


	var home_name: String = LeagueColumns.fit_name(str(fixture.get("home_name", "")), bold,
		name_size, float(places["home_w"]))
	var away_name: String = LeagueColumns.fit_name(str(fixture.get("away_name", "")), bold,
		name_size, float(places["away_w"]))
	InterestNames.run(c, names, str(fixture.get("home_club_id", "")), home_name,
		Vector2(float(places["home_x"]), rect.position.y + head - 6.0), name_size, home_ink, bold)
	InterestNames.run(c, names, str(fixture.get("away_club_id", "")), away_name,
		Vector2(float(places["away_x"]), rect.position.y + head - 6.0), name_size, away_ink, bold)
	if not played:
		return
	var sides := LeagueRoundup.sides(report_of(fixture))
	_paint_side(c, float(places["home_x"]), rect.position.y + head, float(places["home_w"]),
		sides["home"], fonts, line_h)
	_paint_side(c, float(places["away_x"]), rect.position.y + head, float(places["away_w"]),
		sides["away"], fonts, line_h)

static func _paint_side(c: CanvasItem, x: float, top: float, w: float, events: Array,
		fonts: Dictionary, line_h: float) -> void:
	for i in range(events.size()):
		LeagueMarks.line(c, Vector2(x, top + float(i) * line_h), events[i], fonts, w,
			UiChrome.C_TEXT)


