class_name LeagueStartSheet
extends RefCounted

## The season's front door: the New League wizard and the Load library — the
## two sheets that start a season or resume one, as opposed to playing it.
##
## They were poses inside `LeagueSheet`, which is the season hub; the hub was
## carrying three screens, and its own pose shared a file with the field, choice
## and save-row grammar of the front door. Split out, the hub keeps only the hub
## and this sheet owns the screens a player meets before a season is on.
##
## Same contract as the other sheets: `layout()` turns state into rows and chips
## with rects (so a headless test can press them), and `draw_*` paints exactly
## those rects. No sim calls happen here; BACK and the header band come from
## `LeagueExtra`, like every other league sheet.

const HEADER := LeagueChrome.HEADER
const BAR_H := LeagueChrome.BAR_H

var cache := {}
## Dates this sheet painted, with the strip each one occupies (#99).
var hints := DateHints.new()

# ---------------------------------------------------------------- wizard ---

func wizard_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var w := minf(520.0, vp.x - 48.0)
	var y := HEADER + 30.0
	items.append({"id": "name", "kind": "field", "label": "NAME",
		"rect": Rect2(24.0, y, w, 38.0), "value": str(view.get("name", ""))})
	y += 66.0
	# Leagues: at least one, every other one a toggle (#185/#189). The calendar
	# and the clock choices below are shared by whatever set is picked.
	items.append({"id": "", "kind": "caption", "label": "LEAGUES",
		"rect": Rect2(24.0, y - 8.0, w, 10.0)})
	var chosen: Array = view.get("competitions", ["PL"])
	var comps: Array = PLRepository.shared().competitions()
	for i in range(comps.size()):
		var cid := str((comps[i] as Dictionary)["id"])
		var col := i % 2
		var row := i / 2
		items.append({"id": "wleague:" + cid, "kind": "choice",
			"label": str((comps[i] as Dictionary).get("short_name",
				(comps[i] as Dictionary).get("name", cid))),
			"rect": Rect2(24.0 + float(col) * w * 0.52, y + float(row) * 52.0, w * 0.48, 40.0),
			"selected": chosen.has(cid)})
	if not comps.is_empty():
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

# ------------------------------------------------------------------ load ---

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

## The active-league badge on a load row: short names joined with a plus.
static func _league_badge(csv: String) -> String:
	var names: Array = []
	for cid in csv.split(",", false):
		if cid == "":
			continue
		names.append(PLRepository.shared().competition_name(str(cid)))
	return " + ".join(PackedStringArray(names)) if not names.is_empty() else "PL"

# gd-tools: no cover start

func draw_wizard_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "NEW LEAGUE", "GOD-MODE SEASON SETUP")
	if str(view.get("error", "")) != "":
		UiChrome.text(c, Vector2(24.0, vp.y - BAR_H - 10.0), str(view["error"]), 12, UiChrome.C_DANGER, fonts["med"])

func draw_wizard_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var live := str(view.get("focus", "")) == LeagueFieldFocus.WIZARD
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		var id := str(item["id"])
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
				value if value != "" else "League 1", 15, UiChrome.C_TEXT, bold)
			LeagueFieldFocus.caret(c, rect, value, bold, 15, live)
		elif kind == "choice":
			var chosen := bool(item["selected"])
			UiChrome.panel(c, cache, rect,
				UiChrome.C_GOLD.darkened(0.1) if chosen else UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if chosen else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 25.0, str(item["label"]), 12,
				Color(0.06, 0.06, 0.05) if chosen else UiChrome.C_TEXT, bold)
		elif kind == "button":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item.get("primary", false)))

# ------------------------------------------------------------------ load ---

func draw_load_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, _view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "LOAD LEAGUE", "NAMED SEASONS")

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
			var line: String = "%s · %s · %s" % [dated, str(save.get("status", "")), leagues] \
				if dated != "" else "%s · %s" % [str(save.get("status", "")), leagues]
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 32.0), line, 10,
				UiChrome.C_DIM, med)
			if current != "":
				hints.add(DateHints.strip(med, dated,
					Vector2(rect.position.x + 12.0, rect.position.y + 32.0), 10), current)
		elif str(item["kind"]) == "delete":
			UiChrome.panel(c, cache, rect, UiChrome.C_DANGER.darkened(0.35), 5, UiChrome.C_DANGER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + 21.0, "X", 13, UiChrome.C_TEXT, bold)
		elif str(item["kind"]) == "button":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item.get("primary", false)))

# gd-tools: no cover end
