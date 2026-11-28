class_name LeagueEuropeDraw
extends RefCounted


const HEADER := LeagueChrome.HEADER
const ROW_H := 22.0
const ROW_TOUCH_H := 30.0
const POT_LINE := 14.0

var cache := {}
var hints := DateHints.new()


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var width := vp.x - 48.0
	var y := HEADER + 10.0
	var pots: Array = view.get("pots", [])
	var fixtures: Array = view.get("fixtures", [])
	var revealed := int(view.get("revealed", 0))
	var done := bool(view.get("done", false))
	var rail: float = width if touch else minf(460.0, width * 0.46)
	items.append_array(_pots(pots, 24.0, y, rail, touch))
	if touch:
		y += _pots_height(pots, rail, touch) + 12.0
	else:
		y += 12.0
	var x: float = 24.0 if touch else 24.0 + rail + 18.0
	var list_w: float = width if touch else width - rail - 18.0
	var shown := fixtures.size() if done else mini(revealed, fixtures.size())
	var h := ROW_TOUCH_H if touch else ROW_H
	for i in range(shown):
		items.append({"id": "", "kind": "draw_row", "fixture": fixtures[i],
			"rect": Rect2(x, y + float(i) * h, list_w, h - 1.0)})
	if shown == 0:
		items.append({"id": "", "kind": "note", "rect": Rect2(x, y, list_w, 18.0),
			"label": "THE DRAW IS SETTLED — THE CEREMONY OPENS ONE PAIR AT A TIME"})
	items.append(LeagueExtra.back_item(touch))
	var door_y := vp.y - UiChrome.tap_h(40.0, touch) - 8.0
	if done:
		items.append({"id": "europe:draw:open", "kind": "button", "primary": true,
			"label": "OPEN " + str(view.get("short", "")), "pinned": true,
			"rect": Rect2(24.0, door_y, 200.0, UiChrome.tap_h(40.0, touch))})
	else:
		items.append({"id": "europe:draw:skip", "kind": "button", "primary": true,
			"label": "SKIP THE DRAW", "pinned": true,
			"rect": Rect2(24.0, door_y, 200.0, UiChrome.tap_h(40.0, touch))})
	return items


func _pots(pots: Array, x: float, y: float, rail: float, touch: bool) -> Array:
	var out: Array = []
	if touch:
		var w: float = (rail - 8.0) * 0.5
		for i in range(pots.size()):
			var col := i % 2
			var row := i / 2
			out.append({"id": "", "kind": "draw_pot", "pot": pots[i], "index": i,
				"rect": Rect2(x + float(col) * (w + 8.0), y + float(row) * 86.0, w, 82.0)})
		return out
	var w: float = (rail - 10.0) * 0.5
	for i in range(pots.size()):
		var col := i % 2
		var row := i / 2
		out.append({"id": "", "kind": "draw_pot", "pot": pots[i], "index": i,
			"rect": Rect2(x + float(col) * (w + 10.0), y + float(row) * 152.0, w, 146.0)})
	return out


static func _pots_height(pots: Array, rail: float, touch: bool) -> float:
	var rows := ceili(float(pots.size()) / 2.0)
	return float(rows) * (86.0 if touch else 152.0)

# gd-tools: no cover start


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	var touch := bool(view.get("touch", false))
	var title := str(view.get("title", "DRAW"))
	var caption := "%s · %s" % [str(view.get("short", "")), str(view.get("stage", ""))]
	LeagueExtra.header(c, vp, fonts, title, caption, 0.0, true, touch)


func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var fixtures: Array = view.get("fixtures", [])
	var revealed := int(view.get("revealed", 0))
	var done := bool(view.get("done", false))
	for item in items:
		var rect: Rect2 = item["rect"]
		match str(item.get("kind", "")):
			"draw_pot":
				_pot(c, rect, item, fonts)
			"draw_row":
				_row(c, rect, item["fixture"], fonts)
			"button":
				UiChrome.button(c, cache, rect, str(item.get("label", "")), bold,
					bool(item.get("primary", false)))
			"note":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
					str(item.get("label", "")), 11, UiChrome.C_SOFT, med)
	if done:
		var door_h: float = UiChrome.tap_h(40.0, bool(view.get("touch", false)))
		UiChrome.text(c, Vector2(236.0, vp.y - door_h + 16.0),
			"DRAW SETTLED  ·  " + FixtureCalendar.day_label(str(view.get("date", ""))),
			10, UiChrome.C_DIM, bold)
	if not done and not fixtures.is_empty():
		var shown := mini(revealed, fixtures.size())
		UiChrome.text_r(c, vp.x - 24.0, HEADER + 24.0,
			"REVEALING %d / %d" % [shown, fixtures.size()], 9, UiChrome.C_GOLD, bold)


func _pot(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var index := int(item.get("index", 0))
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_BORDER, 1)
	UiChrome.text(c, Vector2(rect.position.x + 8.0, rect.position.y + 15.0),
		"POT %d" % (index + 1), 9, UiChrome.C_GOLD, bold)
	var pot: Array = item.get("pot", [])
	var line := rect.position.y + 32.0
	for club in pot:
		var row: Dictionary = club
		var room: float = rect.size.x - 44.0
		var name: String = LeagueColumns.fit_name(str(row.get("name", "")), med, 9, room)
		UiChrome.text(c, Vector2(rect.position.x + 8.0, line), name, 9, UiChrome.C_SOFT, med)
		UiChrome.text_r(c, rect.end.x - 8.0, line, str(row.get("country", "")), 8,
			UiChrome.C_DIM, bold)
		line += POT_LINE


func _row(c: CanvasItem, rect: Rect2, fixture: Dictionary, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 4)
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	var home: String = LeagueColumns.fit_name(str(fixture.get("home_name", "")), bold, 11,
		rect.size.x * 0.42)
	UiChrome.text(c, Vector2(rect.position.x + 8.0, y), home, 11, UiChrome.C_TEXT, bold)
	UiChrome.text_c(c, rect.position.x + rect.size.x * 0.5, y, "v", 9, UiChrome.C_DIM, med)
	var away: String = LeagueColumns.fit_name(str(fixture.get("away_name", "")), bold, 11,
		rect.size.x * 0.42)
	UiChrome.text(c, Vector2(rect.position.x + rect.size.x * 0.52, y), away, 11,
		UiChrome.C_TEXT, bold)
	if int(fixture.get("matchday", 0)) > 0:
		UiChrome.text_r(c, rect.end.x - 8.0, y, "MD %d" % int(fixture.get("matchday", 0)), 8,
			UiChrome.C_DIM, bold)

# gd-tools: no cover end
