class_name LeagueCupsSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER

const CARD_H := 84.0
const CARD_GAP := 8.0
const NOTE_TOP := 22.0

const DRAW_W := 150.0

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func caption(view: Dictionary) -> String:
	var cups: Array = view.get("cups", [])
	var settled := 0
	for cup in cups:
		if bool((cup as Dictionary).get("complete", false)):
			settled += 1
	return "%d CUPS · %d SETTLED" % [cups.size(), settled]


static func card_lines(cup: Dictionary) -> Array:
	var stage := str(cup.get("stage_name", ""))
	var date := str(cup.get("next_date", ""))
	var line := ""
	if bool(cup.get("complete", false)):
		line = "WINNER  %s" % str(cup.get("winner", ""))
	elif date != "":
		line = "NEXT  %s  ·  %d CLUBS IN" % [FixtureCalendar.day_label(date), int(cup.get("clubs", 0))]
	else:
		line = "%d CLUBS IN" % int(cup.get("clubs", 0))
	return [stage if stage != "" else "NOT DRAWN", line]


static func empty_note(view: Dictionary) -> String:
	if (view.get("cups", []) as Array).is_empty():
		return "This save runs no domestic cups."
	return ""


func cups_layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var y := HEADER + NOTE_TOP
	var w := vp.x - 48.0
	var card_h: float = UiChrome.tap_h(CARD_H, touch)
	var note := empty_note(view)
	if note != "":
		items.append({"id": "", "kind": "note", "label": note,
			"rect": Rect2(24.0, y, w, 24.0)})
	for cup in view.get("cups", []):
		var row: Dictionary = cup
		var rect := Rect2(24.0, y, w, card_h)
		items.append({"id": "cup:" + str(row["id"]), "kind": "cup_card", "cup": row, "rect": rect})
		if bool(row.get("pending_draw", false)):
			var chip_w: float = minf(DRAW_W, w * 0.34)
			items.append({"id": "cupdraw:" + str(row["id"]), "kind": "chip", "label": "REVEAL DRAW",
				"rect": Rect2(rect.end.x - chip_w - 10.0, rect.position.y + card_h - 30.0,
					chip_w, 24.0)})
		y += card_h + CARD_GAP
	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items

# gd-tools: no cover start

func draw_cups_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints_out: DateHints) -> void:
	var bold: Font = fonts["bold"]
	var right: float = LeagueExtra.primary_rect(vp, 140.0, bool(view.get("touch", false))).size.x + 12.0
	LeagueExtra.header(c, vp, fonts, "DOMESTIC CUPS", caption(view), right, true,
		bool(view.get("touch", false)))
	UiChrome.text(c, Vector2(24.0, HEADER + 10.0), "EVERY CUP SETTLES ON THE SEASON CLOCK", 10,
		UiChrome.C_DIM, bold)
	hints_out.add(Rect2(24.0, HEADER + 2.0, 260.0, 12.0), "cups")


func draw_cups_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]),
				12, UiChrome.C_SOFT, med)
		elif kind == "cup_card":
			_paint_card(c, rect, item["cup"], bold, med)
		elif kind == "chip":
			UiChrome.panel(c, cache, rect, UiChrome.C_GOLD.darkened(0.15), 5, UiChrome.C_GOLD, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
				str(item["label"]), 9, Color(0.06, 0.06, 0.05), bold)


func _paint_card(c: CanvasItem, rect: Rect2, cup: Dictionary, bold: Font, med: Font) -> void:
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 7, UiChrome.C_BORDER, 1)
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 8.0, 3.0, rect.size.y - 16.0),
		UiChrome.C_GOLD if bool(cup.get("pending_draw", false)) else UiChrome.C_PANEL_LIGHT)
	var lines := card_lines(cup)
	UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 26.0), str(cup["name"]),
		15, UiChrome.C_TEXT, bold)
	var stage_w: float = UiChrome.text_width(bold, str(lines[0]), 9) + 18.0
	UiChrome.text_r(c, rect.end.x - 12.0 - stage_w, rect.position.y + 25.0, str(cup["full"]), 9,
		UiChrome.C_DIM, med)
	UiChrome.panel(c, cache, Rect2(rect.end.x - 12.0 - stage_w, rect.position.y + 12.0, stage_w, 18.0),
		UiChrome.C_PANEL_LIGHT, 4, UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, rect.end.x - 12.0 - stage_w * 0.5, rect.position.y + 25.0, str(lines[0]), 9,
		UiChrome.C_GOLD, bold)
	var ink: Color = UiChrome.C_GOLD if bool(cup.get("complete", false)) else UiChrome.C_SOFT
	UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.position.y + 48.0), str(lines[1]), 11,
		ink, bold)
	var hint := "TAP TO READ THE BRACKET"
	if bool(cup.get("pending_draw", false)):
		hint = "THE DRAW IS READY"
	UiChrome.text(c, Vector2(rect.position.x + 14.0, rect.end.y - 12.0), hint, 9, UiChrome.C_DIM, med)

# gd-tools: no cover end
