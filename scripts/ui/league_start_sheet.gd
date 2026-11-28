class_name LeagueStartSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER


const SAVE_NAME := "My League Sim"


static func save_name(typed: String) -> String:
	var name := typed.strip_edges()
	return name if name != "" else SAVE_NAME

const TOGGLE_H := 40.0
const TOGGLE_PITCH := 46.0
const MODE_AFTER := 12.0
const ADVANCE_AFTER := 14.0

const CREATE_W := 240.0
const CREATE_H := 46.0
const CREATE_EDGE := 8.0

var cache := {}

var hints := DateHints.new()


static func _league_groups(comps: Array) -> Array:
	var by_country := {}
	var seen: Array = []
	for c in comps:
		var row: Dictionary = c
		var country := LeagueTiers.country_of(str(row["id"]))
		if country == "":
			country = str(row.get("country", ""))
		if country == "":
			country = "OTHER"
		if not by_country.has(country):
			by_country[country] = []
			seen.append(country)
		(by_country[country] as Array).append(row)
	var countries: Array = []
	for country in LeagueTiers.countries():
		if by_country.has(country):
			countries.append(country)
	for country in seen:
		if not countries.has(country):
			countries.append(country)
	var out: Array = []
	for country in countries:
		var rows: Array = by_country[country]
		var sorted: Array = []
		for cid in LeagueTiers.chain(str(country)):
			for row in rows:
				if str((row as Dictionary)["id"]) == str(cid):
					sorted.append(row)
		for row in rows:
			if not sorted.has(row):
				sorted.append(row)
		out.append({"id": str(country), "label": str(country).to_upper(), "leagues": sorted})
	return out

func wizard_layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var w := minf(520.0, vp.x - 48.0)
	var toggle_h: float = UiChrome.tap_h(TOGGLE_H, touch)
	var pitch: float = toggle_h + (TOGGLE_PITCH - TOGGLE_H)
	var y := HEADER + 30.0
	items.append({"id": "name", "kind": "field", "label": "NAME",
		"rect": Rect2(24.0, y, w, 38.0), "value": str(view.get("name", ""))})
	y += 66.0


	items.append({"id": "", "kind": "caption", "label": "LEAGUES",
		"rect": Rect2(24.0, y - 8.0, w, 10.0)})
	var chosen: Array = view.get("competitions", ["PL"])
	var groups := _league_groups(PLRepository.shared().leagues())
	for group in groups:
		items.append({"id": "", "kind": "country", "label": str(group["label"]),
			"rect": Rect2(24.0, y, w, 16.0)})
		y += 22.0
		var leagues: Array = group["leagues"]
		for i in range(leagues.size()):
			var row: Dictionary = leagues[i]
			var cid := str(row["id"])
			var col := i % 2
			var line := i / 2
			items.append({"id": "wleague:" + cid, "kind": "choice",
				"label": str(row.get("short_name", row.get("name", cid))),
				"rect": Rect2(24.0 + float(col) * w * 0.52, y + float(line) * pitch, w * 0.48, toggle_h),
				"selected": chosen.has(cid)})
		y += pitch * float(ceili(float(leagues.size()) / 2.0)) + 6.0
	items.append({"id": "", "kind": "section", "label": "EUROPE",
		"rect": Rect2(24.0, y, w, 16.0)})
	y += 22.0
	items.append({"id": "uefa", "kind": "switch", "label": "UEFA CLUB COMPETITIONS (2026/27)",
		"rect": Rect2(24.0, y, w, toggle_h), "selected": bool(view.get("uefa", false))})
	y += toggle_h + MODE_AFTER
	items.append({"id": "mode:real", "kind": "choice", "label": "REAL FIXTURES",
		"rect": Rect2(24.0, y, w * 0.48, toggle_h), "selected": str(view.get("calendar_mode", "")) == "real"})
	items.append({"id": "mode:generated", "kind": "choice", "label": "GENERATED",
		"rect": Rect2(24.0 + w * 0.52, y, w * 0.48, toggle_h), "selected": str(view.get("calendar_mode", "")) == "generated"})
	y += toggle_h + MODE_AFTER
	items.append({"id": "adv:fixture_days", "kind": "choice", "label": "FIXTURE DAYS",
		"rect": Rect2(24.0, y, w * 0.48, toggle_h), "selected": str(view.get("advance_mode", "")) == "fixture_days"})
	items.append({"id": "adv:every_day", "kind": "choice", "label": "EVERY DAY",
		"rect": Rect2(24.0 + w * 0.52, y, w * 0.48, toggle_h), "selected": str(view.get("advance_mode", "")) == "every_day"})
	y += toggle_h + ADVANCE_AFTER
	items.append(create_item(vp, y, w, touch))
	items.append(LeagueExtra.back_item(touch))
	return items


static func create_item(vp: Vector2, y: float, w: float, touch: bool) -> Dictionary:
	var door_h: float = UiChrome.tap_h(CREATE_H, touch)
	var door_w: float = minf(CREATE_W, w)
	if y + door_h <= vp.y - CREATE_EDGE:
		return {"id": "create", "kind": "button", "label": "CREATE SEASON",
			"rect": Rect2(24.0, y, door_w, door_h), "primary": true}
	var bar: float = bar_h(touch)
	return {"id": "create", "kind": "button", "label": "CREATE SEASON", "primary": true,
		"pinned": true, "bar": bar,
		"rect": Rect2(24.0, vp.y - bar + (bar - door_h) * 0.5, door_w, door_h)}


static func bar_h(touch: bool) -> float:
	return UiChrome.tap_h(CREATE_H, touch) + 12.0


static func bar_of(items: Array) -> float:
	for item in items:
		if str(item.get("id", "")) == "create":
			return float(item.get("bar", 0.0))
	return 0.0


func load_layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var saves: Array = view.get("saves", [])
	var w := minf(620.0, vp.x - 48.0)
	var y := HEADER + 26.0
	var row_h: float = UiChrome.tap_h(40.0, touch)
	var del_h: float = UiChrome.tap_h(32.0, touch)
	var del_w: float = UiChrome.tap_h(40.0, touch)
	var del_x: float = w - 16.0 - del_w if touch else w - 84.0

	for i in range(saves.size()):
		var save: Dictionary = saves[i]
		var row := Rect2(24.0, y, w, row_h)
		items.append({"id": "open:" + str(save["slug"]), "kind": "save_row",
			"rect": row, "save": save})
		items.append({"id": "delete:" + str(save["slug"]), "kind": "delete",
			"rect": Rect2(24.0 + del_x, row.position.y + (row_h - del_h) * 0.5, del_w, del_h),
			"slug": str(save["slug"])})
		y += row_h + 6.0
	items.append(LeagueExtra.back_item(touch))
	return items


static func _league_badge(csv: String) -> String:
	var names: Array = []
	for cid in csv.split(",", false):
		if cid == "":
			continue
		names.append(PLRepository.shared().competition_name(str(cid)))
	return " + ".join(PackedStringArray(names)) if not names.is_empty() else "PL"


static func status_label(status: String) -> String:
	var token := status.strip_edges()
	if token == "in_progress":
		return "IN PROGRESS"
	if token == "complete":
		return "COMPLETE"
	return token.replace("_", " ").to_upper()

# gd-tools: no cover start

func draw_wizard_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "NEW LEAGUE", "GOD-MODE SEASON SETUP", 0.0, true,
		bool(view.get("touch", false)), false)
	if str(view.get("error", "")) != "":
		var bar: float = bar_h(bool(view.get("touch", false)))
		UiChrome.text(c, Vector2(24.0, vp.y - bar - 8.0), str(view["error"]), 12,
			UiChrome.C_DANGER, fonts["med"])

func draw_wizard_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var live := str(view.get("focus", "")) == LeagueFieldFocus.WIZARD
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		var id := str(item["id"])
		if kind == "country" or kind == "section":

			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 10.0), str(item["label"]),
				10, UiChrome.C_GOLD, bold)
			c.draw_rect(Rect2(rect.position.x, rect.position.y + 14.0, rect.size.x, 1.0),
				Color(1, 1, 1, 0.10))
			continue
		if kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 8.0), str(item["label"]),
				10, UiChrome.C_DIM, bold)
		elif id == "mode:real":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "FIXTURES", 10, UiChrome.C_DIM, bold)
		elif id == "adv:fixture_days":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "ADVANCE", 10, UiChrome.C_DIM, bold)
		if kind == "field":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0), "SAVE NAME", 10, UiChrome.C_DIM, bold)
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			var value := str(item["value"])
			UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 25.0),
				value if value != "" else SAVE_NAME, 15,
				UiChrome.C_TEXT if value != "" else UiChrome.C_DIM, bold)
			LeagueFieldFocus.caret(c, rect, value, bold, 15, live)
		elif kind == "choice" or kind == "switch":
			var chosen := bool(item["selected"])
			UiChrome.panel(c, cache, rect,
				UiChrome.C_GOLD.darkened(0.1) if chosen else UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if chosen else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 5.0, str(item["label"]), 12,
				Color(0.06, 0.06, 0.05) if chosen else UiChrome.C_TEXT, bold)
		elif kind == "button":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item.get("primary", false)))


func draw_load_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, _view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "LOAD LEAGUE", "NAMED SEASONS", 0.0, true,
		bool(_view.get("touch", false)), false)

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
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5 - 3.0),
				str(save["name"]), 14, UiChrome.C_TEXT, bold)
			var current := str(save.get("current_date", ""))
			var dated: String = FixtureCalendar.day_label(current)
			var leagues := _league_badge(str(save.get("competitions", "PL")))
			var status := status_label(str(save.get("status", "")))
			var line: String = "%s · %s · %s" % [dated, status, leagues] \
				if dated != "" else "%s · %s" % [status, leagues]
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5 + 12.0),
				line, 10, UiChrome.C_DIM, med)
			if current != "":
				hints.add(DateHints.strip(med, dated,
					Vector2(rect.position.x + 12.0, rect.position.y + rect.size.y * 0.5 + 12.0), 10),
					current)
		elif str(item["kind"]) == "delete":
			UiChrome.panel(c, cache, rect, UiChrome.C_DANGER.darkened(0.35), 5, UiChrome.C_DANGER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 5.0,
				"X", 13, UiChrome.C_TEXT, bold)
		elif str(item["kind"]) == "button":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item.get("primary", false)))

# gd-tools: no cover end
