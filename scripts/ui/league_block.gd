class_name LeagueBlock
extends RefCounted

## The one fixture block every result surface prints (#168): the kick-off time
## or `FT` and the score, both clubs by full name, then each side's events in
## its own column beneath its own name.
##
## Geometry and paint live together so the hub's planner, the calendar's day
## list and the roundup can never drift apart: a played row is the same block in
## all three, only the width and the type it is given change. Names are
## shortened with an ellipsis rather than painted into the other column, and the
## event lines are measured against their own column, so a long scorer or an
## assist bracket never crosses the gutter.
##
## Only the name strips the long press needs are registered here, through the
## caller's own `InterestNames` registry — the same strips the rows have always
## painted (#107).

## A played row with no events still holds the lines it prints.
const BASE := 36.0
## One event line, and the tight line a calendar day row uses.
const LINE := 15.0
const TIGHT_BASE := 32.0
const TIGHT_LINE := 14.0
const GUTTER := 16.0
const INSET := 10.0
## A pending row's kick-off time prints from the row's left edge, and the clubs
## start this far past its ink.
const TIME_X := 8.0
const TIME_GAP := 8.0

## Where the clubs start on a pending row (#309). A season with no kick-off time
## to print — the real-fixture calendar stores none — starts them on the block's
## own inset, the x this block puts its home name at, so a whistle moves neither
## name sideways. A time that is printed is measured, never guessed at.
static func names_x(rect: Rect2, kick: String, font: Font, time_size: int = 10) -> float:
	var inset := rect.position.x + INSET
	if kick == "":
		return inset
	var after := rect.position.x + TIME_X + InterestNames.width(font, kick, time_size) + TIME_GAP
	return maxf(inset, after)

## The two columns a block prints in, from the row it sits in.
static func columns(rect: Rect2) -> Dictionary:
	var mid := rect.position.x + rect.size.x * 0.5 + GUTTER * 0.5
	return {
		"home_x": rect.position.x + INSET,
		"away_x": mid,
		"home_w": maxf(rect.size.x * 0.5 - INSET - GUTTER, 60.0),
		"away_w": maxf(rect.end.x - mid - INSET, 60.0),
	}

## The events of a fixture, from the report the caller holds: the hub and the
## calendar carry them on the fixture row, a roundup carries the report itself.
static func report_of(fixture: Dictionary) -> Dictionary:
	return {"fixture": fixture, "events": fixture.get("events", [])}

## How tall one played fixture's block is at this density. A pending fixture has
## no block: the hub's planner keeps its one-line row.
static func height(fixture: Dictionary, tight: bool = false) -> float:
	if str(fixture.get("status", "")) != "played":
		return 0.0
	var sides := LeagueRoundup.sides(report_of(fixture))
	var rows := maxi((sides["home"] as Array).size(), (sides["away"] as Array).size())
	return (TIGHT_BASE if tight else BASE) + float(rows) * (TIGHT_LINE if tight else LINE)

# gd-tools: no cover start

## Paint the block inside `rect`. `names` registers the club strips the long
## press reads; `home_ink` / `away_ink` carry a followed club's gold.
static func paint(c: CanvasItem, rect: Rect2, fixture: Dictionary, fonts: Dictionary,
		names: InterestNames, home_ink: Color, away_ink: Color, tight: bool = false) -> void:
	var bold: Font = fonts["bold"]
	var name_size := 11 if tight else 13
	var line_h := TIGHT_LINE if tight else LINE
	var head := TIGHT_BASE if tight else BASE
	var places := columns(rect)
	var played := str(fixture.get("status", "")) == "played"
	var kick := str(fixture.get("kickoff_time", ""))
	# A played row leads with FT where the kick-off sat, so the list reads as a
	# results column once the day is done (#124).
	UiChrome.text(c, Vector2(rect.position.x + 8.0, rect.position.y + 15.0),
		"FT" if played else kick, 10, UiChrome.C_GOLD if played else UiChrome.C_DIM, bold)
	var score := "%d  –  %d" % [int(fixture.get("home_goals", 0)), int(fixture.get("away_goals", 0))]
	UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + (15.0 if tight else 16.0), score,
		12 if tight else 13, UiChrome.C_TEXT, bold)
	# The names share one line and each column keeps its own width, so a long
	# name is shortened inside its half instead of running under the score.
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

# gd-tools: no cover end
