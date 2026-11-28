class_name LeagueCupBracket
extends RefCounted


const HEADER := LeagueChrome.HEADER

const COL_W := 260.0
const COL_GAP := 14.0
const COL_HEAD := 34.0
const TIE_H := 44.0
const TIE_GAP := 3.0
const ROUND_GAP := 14.0

const NARROW := 900.0

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func columns_at(vp: Vector2, touch: bool) -> bool:
	return vp.x >= NARROW and not touch


static func tie_height(touch: bool) -> float:
	return maxf(TIE_H, UiChrome.TAP_H) if touch else TIE_H


static func caption(view: Dictionary) -> String:
	if str(view.get("winner", "")) != "":
		return "WINNER  %s" % str(view["winner"])
	var count := (view.get("rounds", []) as Array).size()
	return "%d ROUNDS  ·  %d CLUBS IN" % [count, int(view.get("clubs", 0))]


func bracket_layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var rounds: Array = view.get("rounds", [])
	var row_h := tie_height(touch)
	if rounds.is_empty():
		items.append({"id": "", "kind": "note", "label": "No round has been drawn yet.",
			"rect": Rect2(24.0, HEADER + 20.0, vp.x - 48.0, 24.0)})
		items.append(LeagueExtra.back_item(touch))
		return items
	if columns_at(vp, touch):
		_column_items(items, rounds, row_h)
	else:
		_stack_items(items, rounds, row_h, vp)
	items.append(LeagueExtra.back_item(touch))
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items


func _column_items(items: Array, rounds: Array, row_h: float) -> void:
	var x := 24.0
	var tallest := 0.0
	for row in rounds:
		var round_row: Dictionary = row
		items.append({"id": "", "kind": "col_head", "round": round_row,
			"rect": Rect2(x, HEADER + 14.0, COL_W, COL_HEAD)})
		var y := HEADER + 14.0 + COL_HEAD
		for tie in round_row.get("ties", []):
			items.append(_tie_item(tie, Rect2(x, y, COL_W, row_h)))
			y += row_h + TIE_GAP
		tallest = maxf(tallest, y)
		x += COL_W + COL_GAP
	items.append({"id": "", "kind": "extent",
		"rect": Rect2(24.0, tallest, maxf(x - 24.0, COL_W), 1.0)})


func _stack_items(items: Array, rounds: Array, row_h: float, vp: Vector2) -> void:
	var y := HEADER + 16.0
	for row in rounds:
		var round_row: Dictionary = row
		items.append({"id": "", "kind": "round_head", "round": round_row,
			"rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
		y += 22.0 + 4.0
		for tie in round_row.get("ties", []):
			items.append(_tie_item(tie, Rect2(24.0, y, vp.x - 48.0, row_h)))
			y += row_h + TIE_GAP
		y += ROUND_GAP


func _tie_item(tie: Dictionary, rect: Rect2) -> Dictionary:
	var data: Dictionary = tie
	var played := str(data.get("played_fixture", ""))
	return {"id": ("cupmatch:" + played) if played != "" else "", "kind": "tie",
		"tie": data, "rect": rect}

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints_out: DateHints) -> void:
	var right: float = LeagueExtra.primary_rect(vp, 140.0, bool(view.get("touch", false))).size.x + 12.0
	LeagueExtra.header(c, vp, fonts, str(view.get("name", "CUP")), caption(view), right, true,
		bool(view.get("touch", false)))
	var note := "TAP A PLAYED TIE FOR ITS REPORT"
	if columns_at(vp, bool(view.get("touch", false))):
		note = "SCROLL SIDEWAYS FOR LATER ROUNDS  ·  CLICK A PLAYED TIE FOR ITS REPORT"
	UiChrome.text(c, Vector2(24.0, HEADER + 10.0), note, 10, UiChrome.C_DIM, fonts["bold"])
	hints_out.add(Rect2(24.0, HEADER + 2.0, 300.0, 12.0), "bracket")


func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		match str(item["kind"]):
			"note":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]),
					11, UiChrome.C_SOFT, med)
			"col_head", "round_head":
				_draw_head(c, rect, item["round"], bold, med)
			"tie":
				LeagueCupSheet.paint_tie(c, rect, item["tie"], fonts, cache)
			"extent":
				pass


func _draw_head(c: CanvasItem, rect: Rect2, row: Dictionary, bold: Font, med: Font) -> void:
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0), str(row.get("name", "")), 10,
		UiChrome.C_GOLD, bold)
	var line := FixtureCalendar.day_label(str(row.get("date", "")))
	var count := int(row.get("count", 0))
	if count > 0:
		line += "  ·  %d TIES" % count
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 24.0), line, 9, UiChrome.C_DIM, med)
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 30.0, rect.size.x, 1.0),
		Color(1, 1, 1, 0.10))

# gd-tools: no cover end
