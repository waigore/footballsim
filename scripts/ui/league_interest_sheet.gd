class_name LeagueInterestSheet
extends RefCounted


const HEADER := LeagueExtra.HEADER
const ROW_H := LeagueExtra.ROW_H
const GAP := LeagueExtra.GAP
const FIELD_H := LeagueExtra.FIELD_H

var cache := {}

var hints := DateHints.new()


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	items.append(LeagueExtra.back_item(touch))
	var row_h: float = 48.0 if touch else ROW_H
	var door_h: float = UiChrome.tap_h(ROW_H - 8.0, touch)
	var y := HEADER + 10.0
	items.append({"id": "interest:search", "kind": "field", "value": str(view.get("query", "")),
		"rect": Rect2(24.0, y, vp.x - 48.0, FIELD_H)})
	y += FIELD_H + 8.0
	var results: Array = view.get("results", [])
	for i in range(results.size()):
		var club: Dictionary = results[i]
		items.append({"id": "interest:add:" + str(club["id"]), "kind": "result", "club": club,
			"rect": Rect2(24.0, y + float(i) * (row_h + GAP), vp.x - 48.0, row_h)})
	if not results.is_empty():
		y += float(results.size()) * (row_h + GAP) + 8.0
	items.append({"id": "", "kind": "caption", "label": "YOUR CLUBS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	var clubs: Array = view.get("clubs", [])
	if clubs.is_empty():
		items.append({"id": "", "kind": "note",
			"label": "No teams yet — search above, or long-press a team name anywhere.",
			"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
	for i in range(clubs.size()):
		var club: Dictionary = clubs[i]
		var row := Rect2(24.0, y + float(i) * (row_h + GAP), vp.x - 48.0, row_h)
		items.append({"id": "club:" + str(club["id"]), "kind": "club", "club": club, "rect": row})
		items.append({"id": "interest:remove:" + str(club["id"]), "kind": "remove",
			"rect": Rect2(row.end.x - 96.0, row.position.y + (row_h - door_h) * 0.5, 88.0, door_h)})
	return items

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "TEAMS OF INTEREST", "%d MARKED" % (view.get("clubs", []) as Array).size(),
		0.0, true, bool(view.get("touch", false)))

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var live := str(view.get("focus", "")) == LeagueFieldFocus.INTEREST
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "field":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			var typed := str(item["value"])
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 25.0),
				typed if typed != "" else "SEARCH CLUBS", 14,
				UiChrome.C_TEXT if typed != "" else UiChrome.C_DIM, bold)


			LeagueFieldFocus.caret(c, rect, typed, bold, 14, live)
		elif kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_DIM, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 15.0), str(item["label"]), 11,
				UiChrome.C_SOFT, med)
		elif kind == "result":
			var club: Dictionary = item["club"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, Color(0.96, 0.78, 0.30, 0.35), 1)
			_draw_swatch(c, rect, club)
			UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + rect.size.y * 0.5 + 5.0),
				str(club["name"]), 13, UiChrome.C_TEXT, bold)
			UiChrome.text_r(c, rect.end.x - 12.0, rect.position.y + rect.size.y * 0.5 + 4.0, "ADD  +", 10, UiChrome.C_GOLD, bold)
		elif kind == "club":
			var club: Dictionary = item["club"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			_draw_swatch(c, rect, club)
			UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + rect.size.y * 0.5 + 5.0),
				str(club["name"]), 13, UiChrome.C_GOLD, bold)
			UiChrome.text(c, Vector2(rect.position.x + 18.0, rect.position.y + rect.size.y * 0.5 + 16.0),
				str(club["abbr"]), 8, UiChrome.C_DIM, med)
		elif kind == "remove":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT, 5, UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.get_center().y + 1.0, "REMOVE", 9,
				UiChrome.C_SOFT, bold)

func _draw_swatch(c: CanvasItem, rect: Rect2, club: Dictionary) -> void:
	var colour = club.get("color", UiChrome.C_GOLD)
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 4.0, 3.0, rect.size.y - 8.0), colour)

# gd-tools: no cover end
