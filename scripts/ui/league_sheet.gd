class_name LeagueSheet
extends RefCounted

## Hub, setup wizard and load-list geometry and paint.
##
## The sheets are pure: `layout()` turns the season state into rows and chips
## with rects (so a headless test can press them), and `draw()` paints exactly
## those rects. No sim calls happen here. Doors that must not move (the bottom
## bar and BACK) are tagged `pinned`; everything else scrolls inside LeagueBody.

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

## The wizard's name field: a key either edits the name or is left for the
## screen. Returns `[handled, name]` so the caller never guesses.
static func type_name(name: String, code: int) -> Array:
	if code == KEY_BACKSPACE:
		return [true, name.substr(0, maxi(name.length() - 1, 0))]
	if name.length() >= 24:
		return [false, name]
	var ch := char(code)
	if (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or (ch >= "0" and ch <= "9") or ch == " ":
		return [true, name + (ch.to_upper() if name == "" else ch)]
	return [false, name]

## Edit the name in a wizard/field state dictionary. True when the key belonged
## to the field, so the caller only has to repaint.
static func type_name_into(state: Dictionary, code: int) -> bool:
	var typed: Array = type_name(str(state.get("name", "")), code)
	if not bool(typed[0]):
		return false
	state["name"] = str(typed[1])
	return true

# ------------------------------------------------------------------- hub ---

func hub_layout(vp: Vector2, state: Dictionary) -> Array:
	var items: Array = []
	var plan: Array = state.get("plan", [])
	var top: float = HEADER + (14.0 if not compact(vp) else 8.0)
	var wide := vp.x >= 760.0 and not compact(vp)
	var left_w: float = (vp.x - 72.0) * 0.58 if wide else vp.x - 48.0
	var y := top + 24.0
	for fx in plan:
		var row := Rect2(24.0, y, left_w, ROW_H)
		items.append({"id": "fixture:" + str(fx["id"]), "kind": "row", "rect": row, "fixture": fx})
		var chip := Rect2(row.end.x - 72.0, y + 2.0, 68.0, ROW_H - 4.0)
		items.append({"id": "toggle:" + str(fx["id"]), "kind": "chip", "rect": chip, "fixture": fx})
		y += ROW_H + ROW_GAP
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
			})
			ty += 19.0
	if bool(state.get("can_suggest", false)):
		items.append({"id": "suggest", "kind": "chip", "label": "SUGGEST WATCHES",
			"rect": Rect2(24.0 + left_w - 150.0, top + 2.0, 150.0, 20.0)})
	# Chrome: BACK top-left, CONTINUE top-right. The bottom door bar is gone;
	# every other destination lives in the left panel.
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": LeagueExtra.back_rect()})
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": Rect2(vp.x - 24.0 - 140.0, 12.0, 140.0, 32.0)})
	return items

func wizard_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var w := minf(520.0, vp.x - 48.0)
	var y := HEADER + 30.0
	items.append({"id": "name", "kind": "field", "label": "NAME",
		"rect": Rect2(24.0, y, w, 38.0), "value": str(view.get("name", ""))})
	y += 66.0
	items.append({"id": "mode:real", "kind": "choice", "label": "REAL FIXTURES",
		"rect": Rect2(24.0, y, w * 0.48, 40.0), "selected": str(view.get("calendar_mode", "")) == "real"})
	items.append({"id": "mode:generated", "kind": "choice", "label": "GENERATED",
		"rect": Rect2(24.0 + w * 0.52, y, w * 0.48, 40.0), "selected": str(view.get("calendar_mode", "")) == "generated"})
	y += 52.0
	items.append({"id": "adv:fixture_days", "kind": "choice", "label": "FIXTURE DAYS",
		"rect": Rect2(24.0, y, w * 0.48, 40.0), "selected": str(view.get("advance_mode", "")) == "fixture_days"})
	items.append({"id": "adv:every_day", "kind": "choice", "label": "EVERY DAY",
		"rect": Rect2(24.0 + w * 0.52, y, w * 0.48, 40.0), "selected": str(view.get("advance_mode", "")) == "every_day"})
	y += 54.0
	items.append({"id": "create", "kind": "button", "label": "CREATE SEASON",
		"rect": Rect2(24.0, y, minf(240.0, w), 46.0), "primary": true})
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": LeagueExtra.back_rect()})
	return items

func load_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var saves: Array = view.get("saves", [])
	var w := minf(620.0, vp.x - 48.0)
	var y := HEADER + 26.0
	for i in range(mini(saves.size(), 7)):
		var save: Dictionary = saves[i]
		var row := Rect2(24.0, y, w, 40.0)
		items.append({"id": "open:" + str(save["slug"]), "kind": "save_row",
			"rect": row, "save": save})
		items.append({"id": "delete:" + str(save["slug"]), "kind": "delete",
			"rect": Rect2(row.end.x - 96.0, row.position.y + 5.0, 34.0, 30.0), "slug": str(save["slug"])})
		y += 46.0
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": LeagueExtra.back_rect()})
	return items

## The lane the wide hub's side table occupies, beside the fixture list.
func _hub_table_box(vp: Vector2) -> Rect2:
	var left_w := (vp.x - 72.0) * 0.58
	var tx := 24.0 + left_w + 22.0
	return Rect2(tx, 0.0, vp.x - tx - 24.0, 19.0)

## The side table's column rail: the material compact set the TABLE sheet paints,
## spread across the lane so a club abbreviation's spare room goes to the numbers.
func _hub_table_places(box: Rect2) -> Dictionary:
	return LeagueColumns.of(box, LeagueColumns.COMPACT_COLS, HUB_CLUB_MIN, HUB_CLUB_SHARE)

# gd-tools: no cover start

func draw_hub_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, state: Dictionary,
		_hints: DateHints) -> void:
	# CONTINUE owns the top-right, so a long save name is shortened to the room
	# between it and the header title position.
	var room: float = maxf(vp.x - 24.0 - 140.0 - 136.0 - 10.0, 48.0)
	var title := LeagueColumns.fit_name(str(state.get("name", "LEAGUE")).to_upper(),
		fonts["bold"], 16, room)
	LeagueExtra.header(c, vp, fonts, title)

func draw_hub_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, state: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var date := str(state.get("date", ""))
	var label: String = FixtureCalendar.day_label(date) if date != "" else str(state.get("day", ""))
	var caption := "TODAY'S FIXTURES"
	if label != "":
		caption += " · " + label.to_upper()
	caption += " · GW %d · %d OF %d PLAYED" % [int(state.get("matchday", 1)),
		int(state.get("played", 0)), int(state.get("total", 0))]
	if bool(state.get("settling", false)):
		caption += " · FINISHING THE WATCHED MATCH"
	else:
		for fx in state.get("plan", []):
			if int(fx.get("watched", 0)) == 1:
				caption += " · CONTINUE OPENS THE NEXT WATCH"
				break
	UiChrome.text(c, Vector2(24.0, HEADER + 18.0), caption, 10, UiChrome.C_DIM, bold)
	if date != "":
		hints.add(DateHints.strip(bold, caption, Vector2(24.0, HEADER + 18.0), 10), date)
	if vp.x >= 760.0 and not compact(vp):
		var places := _hub_table_places(_hub_table_box(vp))
		var top: float = HEADER + 14.0
		UiChrome.text(c, Vector2(float(places["club_x"]), top + 16.0), "CLUB", 9,
			UiChrome.C_DIM, bold)
		for col in places["cols"]:
			UiChrome.text_r(c, float(col["right"]), top + 16.0, str(col["label"]), 9,
				UiChrome.C_DIM, bold)
	if (state.get("plan", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 44.0),
			"No fixtures on this day — CONTINUE moves the clock.", 12, UiChrome.C_SOFT, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "row":
			_draw_fixture_row(c, rect, item["fixture"], fonts)
		elif str(item["kind"]) == "chip":
			if str(item["id"]) == "suggest":
				UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, UiChrome.C_GOLD, 1)
				UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
					"SUGGEST WATCHES", 9, UiChrome.C_GOLD, bold)
			else:
				_draw_toggle(c, rect, item["fixture"], bold)
		elif str(item["kind"]) == "table_row":
			_draw_table_row(c, rect, item, fonts)

func _draw_fixture_row(c: CanvasItem, rect: Rect2, fx: Dictionary, fonts: Dictionary) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var time := str(fx.get("kickoff_time", ""))
	if time != "":
		UiChrome.text(c, Vector2(rect.position.x + 8.0, rect.position.y + 17.0), time, 10, UiChrome.C_DIM, med)
	var home_ink: Color = UiChrome.C_GOLD if LeagueInterest.marked(str(fx.get("home_club_id", ""))) else UiChrome.C_TEXT
	var away_ink: Color = UiChrome.C_GOLD if LeagueInterest.marked(str(fx.get("away_club_id", ""))) else UiChrome.C_TEXT
	UiChrome.text(c, Vector2(rect.position.x + 60.0, rect.position.y + 17.0), str(fx["home_abbr"]), 13, home_ink, bold)
	UiChrome.text(c, Vector2(rect.position.x + 60.0 + 46.0, rect.position.y + 17.0), "v", 10, UiChrome.C_DIM, med)
	UiChrome.text(c, Vector2(rect.position.x + 60.0 + 66.0, rect.position.y + 17.0), str(fx["away_abbr"]), 13, away_ink, bold)
	if int(fx.get("suggested", 0)) == 1:
		UiChrome.text_r(c, rect.end.x - 78.0, rect.position.y + 15.0, "TOP-6", 8, UiChrome.C_GOLD, bold)

func _draw_toggle(c: CanvasItem, rect: Rect2, fx: Dictionary, bold: Font) -> void:
	var watch := int(fx.get("watched", 0)) == 1
	var fill: Color = UiChrome.C_GOLD.darkened(0.15) if watch else UiChrome.C_PANEL_LIGHT
	UiChrome.panel(c, cache, rect, fill, 5, UiChrome.C_GOLD if watch else UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 14.0,
		"WATCH" if watch else "AUTO", 9, Color(0.06, 0.06, 0.05) if watch else UiChrome.C_DIM, bold)

func _draw_table_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var row: Dictionary = item["row"]
	var band := str(item["zone"])
	if band != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 3.0, rect.size.y - 4.0), zone_color(band))
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var places: Dictionary = item["places"]
	var y := rect.position.y + 14.0
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row["position"]), 10,
		UiChrome.C_DIM, med)
	var ink: Color = UiChrome.C_GOLD if LeagueInterest.marked(str(row["club_id"])) else UiChrome.C_TEXT
	UiChrome.text(c, Vector2(float(places["club_x"]), y),
		LeagueColumns.fit_name(str(row["club_abbr"]), bold, 12, float(places["club_w"])),
		12, ink, bold)
	for col in places["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, LeagueColumns.text(row, key),
			11 if points else 10, UiChrome.C_TEXT if points else UiChrome.C_SOFT,
			bold if points else med)

# ---------------------------------------------------------------- wizard ---

func draw_wizard_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "NEW LEAGUE", "GOD-MODE SEASON SETUP")
	if str(view.get("error", "")) != "":
		UiChrome.text(c, Vector2(24.0, vp.y - 18.0), str(view["error"]), 12, UiChrome.C_DANGER, fonts["med"])

func draw_wizard_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, _view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		var id := str(item["id"])
		if id == "mode:real":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "FIXTURES", 10, UiChrome.C_DIM, bold)
		elif id == "adv:fixture_days":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "ADVANCE", 10, UiChrome.C_DIM, bold)
		if kind == "field":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "SAVE NAME", 10, UiChrome.C_DIM, bold)
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 25.0),
				str(item["value"]) if str(item["value"]) != "" else "League 1", 15, UiChrome.C_TEXT, bold)
		elif kind == "choice":
			var chosen := bool(item["selected"])
			UiChrome.panel(c, cache, rect,
				UiChrome.C_GOLD.darkened(0.1) if chosen else UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if chosen else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 25.0, str(item["label"]), 12,
				Color(0.06, 0.06, 0.05) if chosen else UiChrome.C_TEXT, bold)
		elif kind == "button":
			draw_button(c, rect, str(item["label"]), bold, bool(item.get("primary", false)))

# ------------------------------------------------------------------ load ---

func draw_load_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	var caption := "OPENING A SAVE UNLOADS THIS SEASON" if bool(view.get("from_season", false)) else "NAMED SEASONS"
	LeagueExtra.header(c, vp, fonts, "LOAD LEAGUE", caption)

func draw_load_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	if (view.get("saves", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 34.0),
			"No saves yet — start a New League from the menu.", 13, UiChrome.C_SOFT, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "save_row":
			var save: Dictionary = item["save"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 17.0),
				str(save["name"]), 14, UiChrome.C_TEXT, bold)
			var current := str(save.get("current_date", ""))
			var dated: String = FixtureCalendar.day_label(current)
			var line: String = "%s · %s" % [dated, str(save.get("status", ""))] if dated != "" else str(save.get("status", ""))
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 32.0), line, 9,
				UiChrome.C_DIM, med)
			if current != "":
				hints.add(DateHints.strip(med, dated,
					Vector2(rect.position.x + 12.0, rect.position.y + 32.0), 9), current)
		elif str(item["kind"]) == "delete":
			UiChrome.panel(c, cache, rect, UiChrome.C_DANGER.darkened(0.35), 5, UiChrome.C_DANGER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 21.0, "X", 13, UiChrome.C_TEXT, bold)
		elif str(item["kind"]) == "button":
			draw_button(c, rect, str(item["label"]), bold, bool(item.get("primary", false)))

# --------------------------------------------------------------- helpers ---

## Bottom action bar: equal-width doors; the first one is the primary.

func draw_button(c: CanvasItem, rect: Rect2, label: String, bold: Font, primary: bool) -> void:
	if primary:
		UiChrome.panel(c, cache, rect, UiChrome.C_GOLD, 7, Color(0.96, 0.78, 0.30, 0.85), 1)
		UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 6.0, label, 15,
			Color(0.06, 0.06, 0.05), bold)
	else:
		UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 7)
		UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 5.0, label, 12,
			UiChrome.C_TEXT, bold)

## The ▶ beside a goal on a match report: a bordered gold chip, sized by the
## caller so the door stays thumb-sized on every platform.
static func draw_play(c: CanvasItem, cache: Dictionary, rect: Rect2, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, Color(0.96, 0.78, 0.30, 0.55), 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 18.0, "▶ PLAY", 10, UiChrome.C_GOLD, bold)

## Month doors and other small fixed chips on a sheet header.
func draw_chip(c: CanvasItem, rect: Rect2, label: String, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 5)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + 17.0, label, 13, UiChrome.C_TEXT, bold)

# gd-tools: no cover end
