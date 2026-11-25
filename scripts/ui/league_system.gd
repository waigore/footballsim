class_name LeagueSystemSheet
extends RefCounted

## The System sheet (#109): the season's own save and exit actions in one place
## instead of a single MENU door. Quick Save rewrites this save, Save As writes a
## copy under a typed name, Load swaps saves (the caller unloads the old one),
## Main Menu leaves the season and Quit asks the shell to close the game.
##
## It sits beside `LeagueSheet`, `LeagueHubSheet` and `LeagueBook` and is its
## own pose: geometry and paint only, no save calls.

const HEADER := 58.0
const ROW_H := 46.0
const ROW_GAP := 8.0

## id, label, caption. Every row is a plain door; the screen owns what each does.
const ACTIONS := [
	{"id": "sys:quick", "label": "QUICK SAVE", "hint": "overwrite this save"},
	{"id": "sys:save", "label": "SAVE AS", "hint": "write a copy under a name"},
	{"id": "sys:load", "label": "LOAD", "hint": "open another save — this one unloads"},
	{"id": "sys:menu", "label": "MAIN MENU", "hint": "leave the season"},
	{"id": "sys:quit", "label": "QUIT", "hint": "close the game"},
]

var cache := {}
## Dates the chrome painted, with the strip each one occupies (#99).
var hints := DateHints.new()

func layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var w := minf(560.0, vp.x - 48.0)
	var x := (vp.x - w) * 0.5
	var y := HEADER + 26.0
	if bool(view.get("naming", false)):
		items.append({"id": "sys:name", "kind": "field", "label": "SAVE NAME",
			"rect": Rect2(x, y + 12.0, w, 40.0), "value": str(view.get("save_name", ""))})
		y += 76.0
		items.append({"id": "sys:commit", "kind": "button", "label": "SAVE", "primary": true,
			"rect": Rect2(x, y, w * 0.48, ROW_H)})
		items.append({"id": "sys:cancel", "kind": "button", "label": "CANCEL",
			"rect": Rect2(x + w * 0.52, y, w * 0.48, ROW_H)})
		y += ROW_H + 18.0
	for action in ACTIONS:
		items.append({"id": str(action["id"]), "kind": "row", "label": str(action["label"]),
			"hint": str(action["hint"]), "rect": Rect2(x, y, w, ROW_H)})
		y += ROW_H + ROW_GAP
	items.append({"id": "back", "kind": "button", "label": "BACK", "pinned": true,
		"rect": LeagueExtra.back_rect()})
	return items

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	var bold: Font = fonts["bold"]
	var date := str(view.get("date", ""))
	var label := FixtureCalendar.day_label(date)
	var parts: Array = []
	if str(view.get("name", "")) != "":
		parts.append(str(view.get("name", "")))
	if label != "":
		parts.append(label)
	LeagueExtra.header(c, vp, fonts, "SYSTEM", " · ".join(PackedStringArray(parts)))
	if date != "":
		hints.add(DateHints.strip_right(bold, label, vp.x - 24.0, 34.0, 10), date)
	# The acknowledgement is painted, never modal: a save lands without an extra
	# press and never hides the next action.
	var status := str(view.get("status", ""))
	var error := str(view.get("error", ""))
	if error != "":
		UiChrome.text(c, Vector2(24.0, HEADER + 14.0), error, 11, UiChrome.C_DANGER, fonts["med"])
	elif status != "":
		UiChrome.text(c, Vector2(24.0, HEADER + 14.0), status, 11, UiChrome.C_LIVE, bold)

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array, _view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		match str(item["kind"]):
			"row":
				UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 7, UiChrome.C_BORDER, 1)
				UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 20.0),
					str(item["label"]), 14, UiChrome.C_TEXT, bold)
				UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 36.0),
					str(item["hint"]), 10, UiChrome.C_DIM, med)
			"field":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y - 8.0),
					str(item["label"]), 10, UiChrome.C_DIM, bold)
				UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
				UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 25.0),
					str(item["value"]), 15, UiChrome.C_TEXT, bold)
			"button":
				UiChrome.button(c, cache, rect, str(item["label"]), bold,
					bool(item.get("primary", false)))

# gd-tools: no cover end
