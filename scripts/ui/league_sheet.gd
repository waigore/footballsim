class_name LeagueSheet
extends RefCounted

## The season hub pose: today's plan beside the table, with CONTINUE.
##
## The hub is pure: `layout()` turns the season state into rows and chips with
## rects (so a headless test can press them), and `draw()` paints exactly those
## rects. No sim calls happen here. Doors that must not move (the bottom bar and
## BACK) are tagged `pinned`; everything else scrolls inside LeagueBody.
##
## The New League wizard and the Load library are the menu-level front door, not
## the hub: they live in `LeagueStartSheet`. The constants below are the league
## surface's shared chrome and are read by every sheet.

const ROW_H := 26.0
const ROW_GAP := 5.0
const BAR_H := 52.0
const HEADER := 58.0
## The hub's side table shows the club abbreviation, not the full name, so its
## club column needs far less room than the TABLE sheet's (#102). The record
## spreads across the lane instead of leaving a dead gap before points.
const HUB_CLUB_MIN := 46.0
const HUB_CLUB_SHARE := 0.14

var cache := {}
## Dates this sheet painted, with the strip each one occupies (#99): the screen's
## overlay paints the weekday for the one under the pointer.
var hints := DateHints.new()
## Club names this sheet painted, with the strip each one occupies (#107): a long
## press on one raises the Teams of Interest menu. Design space, like `hints`.
var names := InterestNames.new()

static func zone_color(band: String) -> Color:
	if band == "ucl":
		return UiChrome.C_GOLD
	if band == "uel":
		return UiChrome.C_LIVE
	if band == "uecl":
		return Color(0.55, 0.72, 0.92)
	if band == "relegation":
		return UiChrome.C_DANGER
	return UiChrome.C_DIM

static func compact(vp: Vector2) -> bool:
	return vp.y < 620.0

# ------------------------------------------------------------------- hub ---

## True when today's plan still holds an unplayed watch, which is exactly when
## CONTINUE's caption has something to promise (#100). A played fixture stops
## counting the moment its result lands, whatever watch flag it kept (#124).
static func watch_pending(plan: Array) -> bool:
	for fx in plan:
		if int(fx.get("watched", 0)) == 1 and str(fx.get("status", "")) != "played":
			return true
	return false

func hub_layout(vp: Vector2, state: Dictionary) -> Array:
	var items: Array = []
	var plan: Array = state.get("plan", [])
	var top: float = HEADER + (14.0 if not compact(vp) else 8.0)
	var interest := LeagueInterestMark.set_of(state.get("interests", []))
	var wide := vp.x >= 760.0 and not compact(vp)
	var left_w: float = (vp.x - 72.0) * 0.58 if wide else vp.x - 48.0
	var y := top + 24.0
	for fx in plan:
		# A played row is a result block: the score line, both full names and
		# each side's events under its own name (#168). A pending row keeps the
		# planner's one line.
		var h: float = maxf(ROW_H, LeagueBlock.height(fx))
		var row := Rect2(24.0, y, left_w, h)
		items.append({"id": "fixture:" + str(fx["id"]), "kind": "row", "rect": row,
			"fixture": fx, "interest": interest})
		# A played row is a result, not a plan: no chip to press, the score takes
		# the chip's place and a tap opens the report (#124).
		if str(fx.get("status", "")) != "played":
			var chip := Rect2(row.end.x - 72.0, y + 2.0, 68.0, ROW_H - 4.0)
			# A followed club's game is on Watch because of the shortlist, not
			# because of this chip: it states the rule and carries no door of its
			# own, so a press falls through to the row and opens the match (#104).
			var followed := LeagueInterestMark.follows(interest, fx)
			items.append({"id": "" if followed else "toggle:" + str(fx["id"]), "kind": "chip",
				"rect": chip, "fixture": fx, "followed": followed})
		y += h + ROW_GAP
	if wide:
		var box := _hub_table_box(vp)
		var places := _hub_table_places(box)
		var rows: Array = state.get("table", [])
		var ty := top + 24.0
		for i in range(mini(rows.size(), 20)):
			if i == 6:
				ty += 6.0
			var band := LeagueRules.zone(int(rows[i]["position"]), state.get("rules", {}))
			items.append({
				"id": "club:" + str(rows[i]["club_id"]), "kind": "table_row",
				"rect": Rect2(box.position.x, ty, box.size.x, 19.0), "row": rows[i],
				"zone": band, "places": places,
				"interested": interest.has(str(rows[i]["club_id"])),
			})
			ty += 19.0
	if bool(state.get("can_suggest", false)):
		items.append({"id": "suggest", "kind": "chip", "label": "SUGGEST WATCHES",
			"rect": Rect2(24.0 + left_w - 150.0, top + 2.0, 150.0, 20.0)})
	# Chrome: BACK top-left, CONTINUE top-right; every other destination lives in
	# the left panel (#105).
	items.append(LeagueExtra.back_item())
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp)})
	return items

## The lane the wide hub's side table occupies, beside the fixture list.
func _hub_table_box(vp: Vector2) -> Rect2:
	var left_w := (vp.x - 72.0) * 0.58
	var tx := 24.0 + left_w + 22.0
	return Rect2(tx, 0.0, vp.x - tx - 24.0, 19.0)

## The side table's column rail: the same compact set the TABLE sheet paints,
## spread across the whole lane so the numbers fill it (a club abbreviation needs
## far less room than a club name).
func _hub_table_places(box: Rect2) -> Dictionary:
	return LeagueColumns.of(box, LeagueColumns.COMPACT_COLS, HUB_CLUB_MIN, HUB_CLUB_SHARE)

# gd-tools: no cover start

func draw_hub_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, state: Dictionary,
		hints: DateHints) -> void:
	var date := str(state.get("date", ""))
	var label: String = FixtureCalendar.day_label(date) if date != "" else str(state.get("day", ""))
	var rest := " · GW %d · %d OF %d PLAYED" % [int(state.get("matchday", 1)),
		int(state.get("played", 0)), int(state.get("total", 0))]
	# A left-behind watch is still being played out: the result lands on its own.
	if bool(state.get("settling", false)):
		rest += " · FINISHING THE WATCHED MATCH"
	var bold: Font = fonts["bold"]
	var name := str(state.get("name", "LEAGUE"))
	# CONTINUE owns the top-right corner, so the title and the caption are fitted
	# inside the lane it leaves (#163, #180).
	var right: float = LeagueExtra.primary_rect(vp).size.x + 12.0
	var band := LeagueExtra.header(c, vp, fonts, name, label + rest, right)
	if date != "" and str(band["caption"]) != "":
		var rect: Rect2 = band["caption_rect"]
		hints.add(Rect2(rect.position.x, 24.0, DateHints.width(bold, label, 10), 14.0), date)

func draw_hub_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, state: Dictionary) -> void:
	hints.clear()
	names.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	## The plan hint rides the caption: the first fixture row starts right under
	## it, so a second line would print through the row. A day that still holds
	## watches says what CONTINUE does with them (#100); a played row never
	## counts, whatever flag it was left with (#124).
	var hint := " · TAP A GAME TO SWITCH AUTO / WATCH" if bool(state.get("can_suggest", false)) else ""
	if watch_pending(state.get("plan", [])):
		hint = " · CONTINUE OPENS THE NEXT WATCH"
	UiChrome.text(c, Vector2(24.0, HEADER + 18.0), "TODAY'S FIXTURES" + hint, 11, UiChrome.C_DIM, bold)
	if vp.x >= 760.0 and not compact(vp):
		var places := _hub_table_places(_hub_table_box(vp))
		var top: float = HEADER + 14.0
		UiChrome.text(c, Vector2(float(places["club_x"]), top + 16.0), "CLUB", 10, UiChrome.C_DIM, bold)
		for col in places["cols"]:
			UiChrome.text_r(c, float(col["right"]), top + 16.0, str(col["label"]), 10,
				UiChrome.C_DIM, bold)
	if (state.get("plan", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 44.0),
			"No fixtures on this day — CONTINUE moves the clock.", 12, UiChrome.C_SOFT, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "row":
			_draw_fixture_row(c, rect, item, fonts)
		elif str(item["kind"]) == "chip":
			if str(item["id"]) == "suggest":
				UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, UiChrome.C_GOLD, 1)
				UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
					"SUGGEST WATCHES", 10, UiChrome.C_GOLD, bold)
			elif bool(item.get("followed", false)):
				LeagueInterestMark.chip(c, cache, rect, bold)
			else:
				_draw_toggle(c, rect, item["fixture"], bold)
		elif str(item["kind"]) == "table_row":
			_draw_table_row(c, rect, item, fonts)

func _draw_fixture_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var fx: Dictionary = item["fixture"]
	var interest: Dictionary = item.get("interest", {})
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var played := str(fx.get("status", "")) == "played"
	# A followed club carries the interest mark: its name is the yellow the
	# planner and the tables share (#104).
	var home_ink := LeagueInterestMark.ink(interest, str(fx.get("home_club_id", "")))
	var away_ink := LeagueInterestMark.ink(interest, str(fx.get("away_club_id", "")))
	if played:
		# The result block: score, both full names, and each side's events under
		# its own name (#168). The chip's old slots are all inside it.
		LeagueBlock.paint(c, rect, fx, fonts, names, home_ink, away_ink)
		return
	# A pending plan row: the kick-off, both clubs by full name, and the chip.
	var line_y := rect.position.y + 17.0
	var time := str(fx.get("kickoff_time", ""))
	if time != "":
		UiChrome.text(c, Vector2(rect.position.x + 8.0, line_y), time, 10, UiChrome.C_DIM, med)
	var x := rect.position.x + 60.0
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

func _draw_toggle(c: CanvasItem, rect: Rect2, fx: Dictionary, bold: Font) -> void:
	var watch := int(fx.get("watched", 0)) == 1
	var fill: Color = UiChrome.C_GOLD.darkened(0.15) if watch else UiChrome.C_PANEL_LIGHT
	UiChrome.panel(c, cache, rect, fill, 5, UiChrome.C_GOLD if watch else UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 14.0,
		"WATCH" if watch else "AUTO", 10, Color(0.06, 0.06, 0.05) if watch else UiChrome.C_DIM, bold)

func _draw_table_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var row: Dictionary = item["row"]
	var band := str(item["zone"])
	if band != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 3.0, rect.size.y - 4.0), zone_color(band))
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var places: Dictionary = item["places"]
	var y := rect.position.y + 14.0
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
	var label: String = LeagueColumns.fit_name(str(row["club_abbr"]), bold, 12, float(places["club_w"]))
	InterestNames.run(c, names, str(row["club_id"]), label, Vector2(float(places["club_x"]), y), 12,
		UiChrome.C_GOLD if bool(item.get("interested", false)) else UiChrome.C_TEXT, bold)
	for col in places["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, LeagueColumns.text(row, key),
			11 if points else 10, UiChrome.C_TEXT if points else UiChrome.C_SOFT,
			bold if points else med)

# gd-tools: no cover end
