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
## The hub keeps no side table: the standings live on the TABLES sheet, and the
## hub's whole width belongs to the day's fixtures (#189).

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
	var left_w: float = vp.x - 48.0
	var y := top + 24.0
	var last_comp := ""
	for fx in plan:
		# A new league on a mixed day opens its own group: the hub reads PL's
		# fixtures, then La Liga's, never one interleaved list.
		var comp := str(fx.get("competition_id", ""))
		if comp != last_comp:
			last_comp = comp
			items.append({"id": "", "kind": "league_head",
				"rect": Rect2(24.0, y, left_w, 18.0),
				"competition": comp, "matchday": int(fx.get("matchday", 1))})
			y += 18.0 + ROW_GAP
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
	if bool(state.get("can_suggest", false)):
		items.append({"id": "suggest", "kind": "chip", "label": "SUGGEST WATCHES",
			"rect": Rect2(24.0 + left_w - 150.0, top + 2.0, 150.0, 20.0)})
	# Chrome: BACK top-left, CONTINUE top-right; every other destination lives in
	# the left panel (#105).
	items.append(LeagueExtra.back_item())
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp)})
	return items

func wizard_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var w := minf(520.0, vp.x - 48.0)
	var y := HEADER + 30.0
	items.append({"id": "name", "kind": "field", "label": "NAME",
		"rect": Rect2(24.0, y, w, 38.0), "value": str(view.get("name", ""))})
	y += 66.0
	items.append({"id": "", "kind": "caption", "label": "LEAGUES",
		"rect": Rect2(24.0, y - 8.0, w, 10.0)})
	var chosen: Array = view.get("competitions", ["PL"])
	var comps: Array = PLRepository.shared().competitions()
	for i in range(comps.size()):
		var cid := str(comps[i]["id"])
		var col := i % 2
		var row := i / 2
		items.append({"id": "wleague:" + cid, "kind": "choice",
			"label": str(comps[i].get("short_name", comps[i].get("name", cid))),
			"rect": Rect2(24.0 + float(col) * w * 0.52, y + float(row) * 52.0, w * 0.48, 40.0),
			"selected": chosen.has(cid)})
	y += 52.0 * float(ceili(float(comps.size()) / 2.0))
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
	items.append(LeagueExtra.back_item())
	return items

func load_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var saves: Array = view.get("saves", [])
	var w := minf(620.0, vp.x - 48.0)
	var y := HEADER + 26.0
	# Every save is laid out; the body scrolls a library longer than one screen (REQ-P5-08).
	for i in range(saves.size()):
		var save: Dictionary = saves[i]
		var row := Rect2(24.0, y, w, 40.0)
		items.append({"id": "open:" + str(save["slug"]), "kind": "save_row",
			"rect": row, "save": save})
		items.append({"id": "delete:" + str(save["slug"]), "kind": "delete",
			"rect": Rect2(row.end.x - 84.0, row.position.y + 4.0, 40.0, 32.0), "slug": str(save["slug"])})
		y += 46.0
	items.append(LeagueExtra.back_item())
	return items

## A league group's heading on a mixed day: the competition name, its gameweek,
## and a rule line so the two groups never blur into one list.
func _draw_league_head(c: CanvasItem, rect: Rect2, item: Dictionary,
		fonts: Dictionary) -> void:
	var name: String = PLRepository.shared().competition_name(str(item.get("competition", "")))
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
		"%s  ·  GW %d" % [name, int(item.get("matchday", 1))], 10, UiChrome.C_GOLD, fonts["bold"])
	var width := UiChrome.text_width(fonts["bold"], "%s  ·  GW 00" % name, 10)
	c.draw_rect(Rect2(rect.position.x + width + 10.0, rect.position.y + 8.0,
		maxf(rect.size.x - width - 10.0, 0.0), 1.0), Color(1, 1, 1, 0.10))

# gd-tools: no cover start

func draw_hub_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, state: Dictionary,
		hints: DateHints) -> void:
	var date := str(state.get("date", ""))
	var label: String = FixtureCalendar.day_label(date) if date != "" else str(state.get("day", ""))
	var parts: Array = []
	for comp in state.get("competitions", []):
		parts.append("%s GW %d" % [str(comp.get("short", comp.get("id", ""))), int(comp.get("matchday", 1))])
	parts.append("%d OF %d PLAYED" % [int(state.get("played", 0)), int(state.get("total", 0))])
	var rest := " · " + " · ".join(PackedStringArray(parts)) if not parts.is_empty() else ""
	# A left-behind watch is still being played out: the result lands on its own.
	if bool(state.get("settling", false)):
		rest += " · FINISHING THE WATCHED MATCH"
	var bold: Font = fonts["bold"]
	var name := str(state.get("name", "LEAGUE"))
	# CONTINUE owns the top-right corner, so the title and the caption are fitted
	# inside the lane it leaves (#163, #180).
	var right: float = LeagueExtra.primary_rect(vp).size.x + 12.0
	var band := _heading(c, vp, fonts, name, label + rest, right)
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
	if (state.get("plan", []) as Array).is_empty():
		UiChrome.text(c, Vector2(24.0, HEADER + 44.0),
			"No fixtures on this day — CONTINUE moves the clock.", 12, UiChrome.C_SOFT, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		if str(item["kind"]) == "league_head":
			_draw_league_head(c, rect, item, fonts)
		elif str(item["kind"]) == "row":
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

# ---------------------------------------------------------------- wizard ---

func draw_wizard_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	_heading(c, vp, fonts, "NEW LEAGUE", "GOD-MODE SEASON SETUP")
	if str(view.get("error", "")) != "":
		UiChrome.text(c, Vector2(24.0, vp.y - BAR_H - 10.0), str(view["error"]), 12, UiChrome.C_DANGER, fonts["med"])

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
		if kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 8.0), str(item["label"]), 10, UiChrome.C_DIM, bold)
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

func draw_load_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, _view: Dictionary,
		_hints: DateHints) -> void:
	_heading(c, vp, fonts, "LOAD LEAGUE", "NAMED SEASONS")

## The active-league badge on a load row: short names joined with a plus.
static func _league_badge(csv: String) -> String:
	var names: Array = []
	for cid in csv.split(",", false):
		if cid == "":
			continue
		names.append(PLRepository.shared().competition_name(str(cid)))
	return " + ".join(PackedStringArray(names)) if not names.is_empty() else "PL"

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
			var leagues := _league_badge(str(save.get("competitions", "PL")))
			var line: String = "%s · %s · %s" % [dated, str(save.get("status", "")), leagues] if dated != "" else "%s · %s" % [str(save.get("status", "")), leagues]
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 32.0), line, 10,
				UiChrome.C_DIM, med)
			if current != "":
				hints.add(DateHints.strip(med, dated,
					Vector2(rect.position.x + 12.0, rect.position.y + 32.0), 10), current)
		elif str(item["kind"]) == "delete":
			UiChrome.panel(c, cache, rect, UiChrome.C_DANGER.darkened(0.35), 5, UiChrome.C_DANGER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 21.0, "X", 13, UiChrome.C_TEXT, bold)
		elif str(item["kind"]) == "button":
			draw_button(c, rect, str(item["label"]), bold, bool(item.get("primary", false)))

# --------------------------------------------------------------- helpers ---

## Bottom action bar: equal-width doors; the first one is the primary. The
## grammar itself is `UiChrome.button`, shared with the menu, the System dialog,
## the fixture picker and the encyclopedia.
func draw_button(c: CanvasItem, rect: Rect2, label: String, bold: Font,
		primary: bool, disabled: bool = false) -> void:
	UiChrome.button(c, cache, rect, label, bold, primary, -1, "", not disabled)

## The ▶ beside a goal on a match report: a bordered gold chip, sized by the
## caller so the door stays thumb-sized on every platform.
static func draw_play(c: CanvasItem, cache: Dictionary, rect: Rect2, bold: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 6, Color(0.96, 0.78, 0.30, 0.55), 1)
	var mid: float = rect.position.y + rect.size.y * 0.5 + UiChrome.RISE
	UiChrome.text_c(c, rect.get_center().x, mid, "▶ PLAY", 10, UiChrome.C_GOLD, bold)

## Small fixed chips on a sheet header (the calendar's month doors).
func draw_chip(c: CanvasItem, rect: Rect2, label: String, bold: Font) -> void:
	UiChrome.chip(c, cache, rect, label, bold)

func _heading(c: CanvasItem, vp: Vector2, fonts: Dictionary, title: String, caption: String,
		right: float = 0.0) -> Dictionary:
	# BACK owns the top-left corner on the hub, the wizard and the load list too
	# (#163), so the title takes the same rail as every other league sheet. The
	# header returns the band it really painted after fitting (#180).
	return LeagueExtra.header(c, vp, fonts, title, caption, right)

# gd-tools: no cover end
