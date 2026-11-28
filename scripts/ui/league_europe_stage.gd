class_name LeagueEuropeStage
extends RefCounted


const HEADER := LeagueChrome.HEADER
const RAIL_TOP := HEADER + 30.0
const CHIP_W := 84.0
const CHIP_H := 24.0
const CHIP_GAP := 6.0
const ROW_H := 22.0
const TAP_ROW := 45.0
const TIE_H := 50.0
const TAP_TIE := 64.0
const NUM_W := 26.0
const CLUB_MIN := 150.0

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func row_height(touch: bool) -> float:
	return TAP_ROW if touch else ROW_H


static func tie_height(touch: bool) -> float:
	return TAP_TIE if touch else TIE_H


static func chip_height(touch: bool) -> float:
	return UiChrome.tap_h(CHIP_H, touch)


static func rail_rows(vp: Vector2, count: int, touch: bool) -> int:
	var per: int = maxi(int(floor((vp.x - 48.0 + CHIP_GAP) / (CHIP_W + CHIP_GAP))), 1)
	return int(ceil(float(count) / float(per)))


static func body_top(vp: Vector2, count: int, touch: bool) -> float:
	return RAIL_TOP + float(rail_rows(vp, count, touch)) * (chip_height(touch) + CHIP_GAP) + 8.0


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	if not bool(view.get("on", false)):
		items.append(LeagueExtra.back_item(touch))
		return items
	items.append_array(_rail(vp, view.get("rounds", []), str(view.get("round", "")), touch))
	var round_id := str(view.get("round", ""))
	if round_id == LeagueUefa.LEAGUE_STAGE:
		items.append_array(_table(vp, view, touch))
	else:
		items.append_array(_ties(vp, view, touch))
	items.append(LeagueExtra.back_item(touch))
	var back: Rect2 = LeagueExtra.back_rect(touch)
	items.append({"id": "europehub", "kind": "button", "label": "EUROPE", "pinned": true,
		"rect": Rect2(back.end.x + 8.0, back.position.y, 110.0, back.size.y)})
	return items


func _rail(vp: Vector2, rounds: Array, current: String, touch: bool) -> Array:
	var items: Array = []
	var h: float = chip_height(touch)
	var per: int = maxi(int(floor((vp.x - 48.0 + CHIP_GAP) / (CHIP_W + CHIP_GAP))), 1)
	for i in range(rounds.size()):
		var row: Dictionary = rounds[i]
		var col := i % per
		var line := i / per
		items.append({"id": "europeround:" + str(row.get("id", "")), "kind": "rail",
			"round": row, "selected": str(row.get("id", "")) == current,
			"rect": Rect2(24.0 + float(col) * (CHIP_W + CHIP_GAP),
				RAIL_TOP + float(line) * (h + CHIP_GAP), CHIP_W, h)})
	return items


func _table(vp: Vector2, view: Dictionary, touch: bool) -> Array:
	var items: Array = []
	var rh: float = row_height(touch)
	var top: float = body_top(vp, (view.get("rounds", []) as Array).size(), touch) + 18.0
	items.append({"id": "", "kind": "table_head", "rect": Rect2(24.0, top, vp.x - 48.0, 16.0)})
	top += 18.0
	var rows: Array = view.get("table", [])
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		items.append({"id": "club:" + str(row.get("club_id", "")), "kind": "table_row", "row": row,
			"rect": Rect2(24.0, top + float(i) * rh, vp.x - 48.0, rh - 1.0)})
	top += float(rows.size()) * rh + 8.0
	items.append({"id": "", "kind": "legend", "rect": Rect2(24.0, top, vp.x - 48.0, 16.0)})
	return items


func _ties(vp: Vector2, view: Dictionary, touch: bool) -> Array:
	var items: Array = []
	var th: float = tie_height(touch)
	var top: float = body_top(vp, (view.get("rounds", []) as Array).size(), touch)
	var ties: Array = view.get("ties", [])
	if ties.is_empty():
		items.append({"id": "", "kind": "empty",
			"rect": Rect2(24.0, top + 18.0, vp.x - 48.0, 20.0)})
		return items
	for i in range(ties.size()):
		var tie: Dictionary = ties[i]
		var target := ""
		if str(tie.get("report", "")) != "":
			target = "match:" + str(tie.get("report", ""))
		items.append({"id": target, "kind": "tie", "tie": tie,
			"rect": Rect2(24.0, top + float(i) * (th + 4.0), vp.x - 48.0, th)})
	return items

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints_out: DateHints) -> void:
	var bold: Font = fonts["bold"]
	var card: Dictionary = view.get("card", {})
	var title := str(card.get("short", "EUROPE"))
	var caption := ""
	if str(card.get("winner", "")) != "":
		caption = "%s  %s" % [str(card.get("winner_name", "")), str(card.get("score_line", ""))]
	elif str(card.get("next", "")) != "":
		caption = "NEXT UEFA NIGHT  " + FixtureCalendar.day_label(str(card.get("next", "")))
	LeagueExtra.header(c, vp, fonts, title, caption, 0.0, true, bool(view.get("touch", false)))
	var stage := str(card.get("stage_label", ""))
	if stage != "":
		UiChrome.text(c, Vector2(LeagueExtra.TITLE_X, HEADER - 14.0), stage, 10,
			UiChrome.C_DIM, bold)
	if str(card.get("next", "")) != "":
		var at := Vector2(vp.x - 24.0 - UiChrome.text_width(bold, caption, 10), 24.0)
		if str(caption).begins_with("NEXT"):
			hints_out.add(Rect2(at.x, at.y - 10.0, UiChrome.text_width(bold, caption, 10), 13.0),
				str(card.get("next", "")))


func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	names.clear()
	if not bool(view.get("on", false)):
		UiChrome.text(c, Vector2(24.0, HEADER + 20.0),
			"No UEFA competition is running in this save.", 13, UiChrome.C_SOFT, fonts["med"])
		return
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "rail":
			_paint_rail(c, rect, item, fonts)
		elif kind == "table_head":
			_paint_table_head(c, rect, fonts)
		elif kind == "table_row":
			_paint_table_row(c, rect, item, fonts)
		elif kind == "tie":
			_paint_tie(c, rect, item["tie"], fonts)
		elif kind == "legend":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 11.0),
				LeagueEurope.zone_caption(), 9, UiChrome.C_DIM, fonts["bold"])
		elif kind == "empty":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
				"This round has not been drawn yet.", 12, UiChrome.C_SOFT, fonts["med"])


func _paint_rail(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var round: Dictionary = item["round"]
	var selected := bool(item["selected"])
	var state := str(round.get("state", "ahead"))
	var fill := UiChrome.C_PANEL
	var ink := UiChrome.C_SOFT
	if selected:
		fill = UiChrome.C_GOLD.darkened(0.12)
		ink = Color(0.06, 0.06, 0.05)
	elif state == "done":
		ink = UiChrome.C_DIM
	UiChrome.panel(c, cache, rect, fill, 5,
		UiChrome.C_GOLD if selected else UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
		str(round.get("label", "")), 10, ink, fonts["bold"])


func _columns(vp: Vector2) -> Dictionary:
	var row_w: float = vp.x - 48.0
	var num := NUM_W
	var club_x := 24.0 + 26.0
	var club_w: float = maxf(row_w - 26.0 - num * 8.0, CLUB_MIN)
	var out := {"club_x": club_x, "club_w": club_w, "cols": []}
	var x := club_x + club_w
	for key in ["P", "W", "D", "L", "GF", "GA", "GD", "PTS"]:
		out["cols"].append({"key": key, "right": x + 26.0 - 6.0})
		x += num
	return out


func _paint_table_head(c: CanvasItem, rect: Rect2, fonts: Dictionary) -> void:
	var places := _columns(Vector2(rect.size.x + 48.0, rect.size.y))
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 11.0), "#", 9,
		UiChrome.C_DIM, fonts["bold"])
	UiChrome.text(c, Vector2(float(places["club_x"]), rect.position.y + 11.0), "CLUB", 9,
		UiChrome.C_DIM, fonts["bold"])
	for col in places["cols"]:
		UiChrome.text_r(c, float(col["right"]), rect.position.y + 11.0, str(col["key"]), 9,
			UiChrome.C_DIM, fonts["bold"])


func _paint_table_row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var row: Dictionary = item["row"]
	var band := str(row.get("zone", ""))
	if band != "":
		c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 3.0, rect.size.y - 4.0),
			_zone_color(band))
	var places := _columns(Vector2(rect.size.x + 48.0, rect.size.y))
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	UiChrome.text(c, Vector2(rect.position.x + 2.0, y), "%d" % int(row.get("position", 0)), 10,
		UiChrome.C_DIM, fonts["med"])
	var name: String = LeagueColumns.fit_name(str(row.get("club_name", "")), fonts["bold"], 11,
		float(places["club_w"]) - 8.0)
	UiChrome.text(c, Vector2(float(places["club_x"]), y), name, 11, UiChrome.C_TEXT, fonts["bold"])
	var values := [int(row.get("played", 0)), int(row.get("won", 0)), int(row.get("drawn", 0)),
		int(row.get("lost", 0)), int(row.get("gf", 0)), int(row.get("ga", 0)),
		int(row.get("gd", 0)), int(row.get("points", 0))]
	for i in range(places["cols"].size()):
		var col: Dictionary = places["cols"][i]
		var points := str(col["key"]) == "PTS"
		UiChrome.text_r(c, float(col["right"]), y, str(values[i]), 10 if points else 9,
			UiChrome.C_TEXT if points else UiChrome.C_SOFT,
			fonts["bold"] if points else fonts["med"])


func _paint_tie(c: CanvasItem, rect: Rect2, tie: Dictionary, fonts: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var played := bool(tie.get("played", false))
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 5, UiChrome.C_BORDER, 1)
	var room := rect.size.x - 150.0
	var home := str(tie.get("home_name", ""))
	var away := str(tie.get("away_name", ""))
	var winner := str(tie.get("winner", ""))
	UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 19.0),
		LeagueColumns.fit_name(home, bold, 11, room), 11,
		UiChrome.C_GOLD if winner == str(tie.get("home", "")) else UiChrome.C_TEXT, bold)
	UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 35.0),
		LeagueColumns.fit_name(away, bold, 11, room), 11,
		UiChrome.C_GOLD if winner == str(tie.get("away", "")) else UiChrome.C_SOFT, bold)
	var line := str(tie.get("score_line", ""))
	UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 19.0, line if line != "" else "—", 11,
		UiChrome.C_TEXT, bold)
	var legs: Array = tie.get("leg_lines", [])
	UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 35.0,
		" · ".join(PackedStringArray(legs)) if not legs.is_empty() else "DRAWN", 9,
		UiChrome.C_DIM, med)
	var badge := str(tie.get("drop", ""))
	if badge == "":
		badge = str(tie.get("arrived", ""))
	if badge != "":
		UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.end.y - 5.0), badge, 9,
			UiChrome.C_GOLD, bold)
	if played:
		UiChrome.text_r(c, rect.end.x - 10.0, rect.end.y - 5.0, "REPORT", 8, UiChrome.C_DIM, med)


static func _zone_color(band: String) -> Color:
	if band == "r16":
		return UiChrome.C_GOLD
	if band == "kopo":
		return UiChrome.C_LIVE
	return UiChrome.C_DANGER

# gd-tools: no cover end
