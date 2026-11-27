class_name LeaguePlanRows
extends RefCounted

## The hub's two row grammars: a fixture on today's plan, and a club on the side
## table.
##
## A plan row is a result block once the fixture is played — the shared
## `LeagueBlock` every result surface prints (#168) — and the planner's single
## line while it is pending: kick-off, both clubs by full name, and the
## AUTO/WATCH chip, or the shortlist's own mark when a followed club put the
## game on Watch (#104).
##
## A side-table row is the compact record: the place, the club abbreviation and
## the number rail `LeagueColumns` measures, with the zone band at its edge.
##
## Both paint in the rect they are handed, like every other sheet: no canvas
## transform, so a name's strip and the row's box are always the same design-space
## numbers the layout produced.

## The planner's line sits this far down a pending row.
const LINE := 17.0

## Paint one plan row. `home_ink` / `away_ink` are the interest mark's inks,
## resolved by the sheet that laid the row. `names` is the sheet's own registry,
## so the long press reads exactly the strips this row painted (#107).
static func paint_fixture(c: CanvasItem, rect: Rect2, fx: Dictionary, fonts: Dictionary,
		cache: Dictionary, names: InterestNames, home_ink: Color, away_ink: Color) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	if str(fx.get("status", "")) == "played":
		# The result block: score, both full names, and each side's events under
		# its own name (#168). The chip's old slots are all inside it.
		LeagueBlock.paint(c, rect, fx, fonts, names, home_ink, away_ink)
		return
	var x := rect.position.x
	var line_y := rect.position.y + LINE
	var time := str(fx.get("kickoff_time", ""))
	if time != "":
		UiChrome.text(c, Vector2(x + LeagueBlock.TIME_X, line_y), time, 10, UiChrome.C_DIM, med)
	# A season with no kick-off time — the real-fixture calendar stores none —
	# starts its clubs on the block's inset, so the whistle that swaps this row
	# for the result block moves no name sideways (#309).
	x = LeagueBlock.names_x(rect, time, med, 10)
	var room := maxf((rect.end.x - 96.0 - x) * 0.46, 60.0)
	var home_name: String = LeagueColumns.fit_name(str(fx.get("home_name", "")), bold, 13, room)
	x += InterestNames.run(c, names, str(fx.get("home_club_id", "")), home_name,
		Vector2(x, line_y), 13, home_ink, bold) + 8.0
	UiChrome.text(c, Vector2(x, line_y), "v", 10, UiChrome.C_DIM, med)
	x += InterestNames.width(med, "v", 10) + 8.0
	var away_name: String = LeagueColumns.fit_name(str(fx.get("away_name", "")), bold, 13,
		maxf(rect.end.x - 96.0 - x, 60.0))
	InterestNames.run(c, names, str(fx.get("away_club_id", "")), away_name,
		Vector2(x, line_y), 13, away_ink, bold)
	if int(fx.get("suggested", 0)) == 1:
		UiChrome.text_r(c, rect.end.x - 78.0, rect.position.y + 15.0, "TOP-6", 10, UiChrome.C_GOLD, bold)

## The AUTO/WATCH chip of a pending row (#100).
static func paint_toggle(c: CanvasItem, rect: Rect2, fx: Dictionary, cache: Dictionary,
		bold: Font) -> void:
	var watch := int(fx.get("watched", 0)) == 1
	var fill: Color = UiChrome.C_GOLD.darkened(0.15) if watch else UiChrome.C_PANEL_LIGHT
	UiChrome.panel(c, cache, rect, fill, 5, UiChrome.C_GOLD if watch else UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 14.0,
		"WATCH" if watch else "AUTO", 10, Color(0.06, 0.06, 0.05) if watch else UiChrome.C_DIM, bold)

## Paint one side-table club row: the zone band, the place, the abbreviation (or
## the full name once a followed club is amber), then the rail.
static func paint_table_row(c: CanvasItem, rect: Rect2, row: Dictionary, zone: String,
		places: Dictionary, interested: bool, fonts: Dictionary, names: InterestNames) -> void:
	if zone != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 3.0, rect.size.y - 4.0),
			LeagueChrome.zone_color(zone))
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var y := rect.position.y + 14.0
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row["position"]), 10,
		UiChrome.C_DIM, med)
	var label: String = LeagueColumns.fit_name(str(row["club_abbr"]), bold, 12,
		float(places["club_w"]))
	InterestNames.run(c, names, str(row["club_id"]), label, Vector2(float(places["club_x"]), y), 12,
		UiChrome.C_GOLD if interested else UiChrome.C_TEXT, bold)
	for col in places["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, LeagueColumns.text(row, key),
			11 if points else 10, UiChrome.C_TEXT if points else UiChrome.C_SOFT,
			bold if points else med)
