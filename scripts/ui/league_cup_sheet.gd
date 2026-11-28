class_name LeagueCupSheet
extends RefCounted


const HEADER := LeagueChrome.HEADER

const ROUND_H := 22.0
const TIE_H := 44.0
const TIE_GAP := 3.0
const SECTION_GAP := 12.0
const BAND_NOTE := 6.0

const SCORE_W := 96.0

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func row_height(touch: bool) -> float:
	return maxf(TIE_H, UiChrome.TAP_H) if touch else TIE_H


static func caption(view: Dictionary) -> String:
	if bool(view.get("inactive", false)):
		return "NOT IN THIS SAVE"
	var parts: Array = []
	if str(view.get("stage_name", "")) != "":
		parts.append("STAGE  %s" % str(view["stage_name"]))
	if str(view.get("next_date", "")) != "":
		parts.append("NEXT  %s" % FixtureCalendar.day_label(str(view["next_date"])))
	if str(view.get("winner", "")) != "":
		parts = ["WINNER  %s" % str(view["winner"])]
	return "  ·  ".join(PackedStringArray(parts))


static func round_caption(row: Dictionary) -> String:
	var count := int(row.get("count", 0))
	var head := "%s  ·  %s" % [str(row.get("name", "")), FixtureCalendar.day_label(str(row.get("date", "")))]
	if count == 1:
		head += "  ·  1 TIE"
	else:
		head += "  ·  %d TIES" % count
	if bool(row.get("complete", false)):
		head += "  ·  SETTLED"
	return head


static func fixture_door(tie: Dictionary) -> String:
	var played := str(tie.get("played_fixture", ""))
	return "cupmatch:" + played if played != "" else ""


func cup_layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var y := HEADER + 20.0
	var w := vp.x - 48.0
	var row_h := row_height(touch)
	if bool(view.get("inactive", false)):
		items.append({"id": "", "kind": "note", "label": "This save does not run this cup.",
			"rect": Rect2(24.0, y, w, 24.0)})
		items.append(LeagueExtra.back_item(touch))
		return items
	var rounds: Array = view.get("rounds", [])
	if rounds.is_empty():
		items.append({"id": "", "kind": "note", "label": "No round has been drawn yet.",
			"rect": Rect2(24.0, y, w, 24.0)})
	if str(view.get("field", "")) != "":
		items.append({"id": "", "kind": "field", "label": str(view["field"]),
			"rect": Rect2(24.0, y, w, 24.0)})
		y += 26.0
	for row in rounds:
		var round_row: Dictionary = row
		items.append({"id": "cupround:%s:%s" % [str(view["id"]), str(round_row["id"])],
			"kind": "round", "round": round_row, "rect": Rect2(24.0, y, w, ROUND_H)})
		if bool(round_row.get("drawn", false)):
			var door: Dictionary = {"id": "cupdraw:%s:%s" % [str(view["id"]), str(round_row["id"])],
				"kind": "chip",
				"label": "DRAW" if not bool(round_row.get("selected", false)) else "REVEAL DRAW",
				"rect": Rect2(24.0 + w - 108.0, y - 4.0, 108.0, 24.0)}
			items.append(door)
		y += ROUND_H + BAND_NOTE
		if not bool(round_row.get("selected", false)):
			continue
		var ties: Array = view.get("ties", [])
		if ties.is_empty():
			items.append({"id": "", "kind": "note", "label": "Awaiting the draw.",
				"rect": Rect2(24.0, y, w, 20.0)})
			y += 24.0
		for tie in ties:
			var tie_data: Dictionary = tie
			var rect := Rect2(24.0, y, w, row_h)
			items.append({"id": fixture_door(tie_data), "kind": "tie", "tie": tie_data, "rect": rect})
			y += row_h + TIE_GAP
		items.append({"id": "", "kind": "extent", "rect": Rect2(24.0, y, w, SECTION_GAP)})
		y += SECTION_GAP
	items.append(LeagueExtra.back_item(touch))
	if not bool(view.get("inactive", false)):
		var cont: Rect2 = LeagueExtra.primary_rect(vp, 140.0, touch)
		items.append({"id": "cupbracket:%s:%s" % [str(view["id"]), str(view.get("chosen", ""))],
			"kind": "button", "label": "BRACKET", "primary": false, "pinned": true,
			"rect": Rect2(cont.position.x - 150.0, cont.position.y,
				minf(140.0, maxf(cont.position.x - 32.0, 90.0)), cont.size.y)})
	items.append({"id": "continue", "kind": "button", "label": "CONTINUE", "primary": true,
		"pinned": true, "rect": LeagueExtra.primary_rect(vp, 140.0, touch)})
	return items

# gd-tools: no cover start

func draw_cup_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints_out: DateHints) -> void:
	var bold: Font = fonts["bold"]
	var right: float = LeagueExtra.primary_rect(vp, 140.0, bool(view.get("touch", false))).size.x + 12.0
	var band := LeagueExtra.header(c, vp, fonts, str(view.get("name", "CUP")), caption(view), right,
		true, bool(view.get("touch", false)))
	if str(view.get("next_date", "")) != "" and str(band.get("caption", "")) != "":
		var rect: Rect2 = band["caption_rect"]
		hints_out.add(Rect2(rect.position.x, 24.0, 120.0, 14.0), str(view["next_date"]))
	if not bool(view.get("inactive", false)):
		var cont: Rect2 = LeagueExtra.primary_rect(vp, 140.0, bool(view.get("touch", false)))
		var door := Rect2(cont.position.x - 150.0, cont.position.y,
			minf(140.0, maxf(cont.position.x - 32.0, 90.0)), cont.size.y)
		UiChrome.panel(c, cache, door, UiChrome.C_PANEL_LIGHT, 7, UiChrome.C_BORDER, 1)
		UiChrome.text_c(c, door.get_center().x, door.position.y + door.size.y * 0.5 + 5.0,
			"BRACKET", 12, UiChrome.C_TEXT, bold)


func draw_cup_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
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
			"field":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]),
					10, UiChrome.C_GOLD, bold)
			"round":
				var row: Dictionary = item["round"]
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 13.0),
					round_caption(row), 10,
					UiChrome.C_GOLD if bool(row.get("selected", false)) else UiChrome.C_DIM, bold)
				c.draw_rect(Rect2(rect.position.x, rect.end.y - 4.0, rect.size.x, 1.0),
					Color(1, 1, 1, 0.10))
			"chip":
				UiChrome.panel(c, cache, rect, UiChrome.C_GOLD.darkened(0.15), 5, UiChrome.C_GOLD, 1)
				UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
					str(item["label"]), 9, Color(0.06, 0.06, 0.05), bold)
			"tie":
				paint_tie(c, rect, item["tie"], fonts, cache)
			"extent":
				pass


static func paint_tie(c: CanvasItem, rect: Rect2, tie: Dictionary, fonts: Dictionary,
		cache_in: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var played := bool(tie.get("played", false))
	UiChrome.panel(c, cache_in, rect, UiChrome.C_PANEL, 5,
		UiChrome.C_GOLD if played else UiChrome.C_BORDER, 1)
	var score_w: float = SCORE_W if played else 0.0
	var name_x := rect.position.x + 10.0
	var room: float = rect.size.x - score_w - 34.0
	var line1 := rect.position.y + 17.0
	var line2 := rect.position.y + 32.0
	var winner := str(tie.get("winner", ""))
	var home_ink: Color = UiChrome.C_GOLD if winner != "" and winner == str(tie.get("home", "")) \
		else UiChrome.C_TEXT
	var away_ink: Color = UiChrome.C_GOLD if winner != "" and winner == str(tie.get("away", "")) \
		else UiChrome.C_TEXT
	var home_name: String = LeagueColumns.fit_name(str(tie.get("home_name", "")), bold, 12, room)
	var away_name: String = LeagueColumns.fit_name(str(tie.get("away_name", "")), bold, 12, room)
	UiChrome.text(c, Vector2(name_x, line1), home_name, 12, home_ink, bold)
	UiChrome.text(c, Vector2(name_x, line2), away_name, 12, away_ink, bold)
	if not played:
		UiChrome.text_r(c, rect.end.x - 10.0, rect.get_center().y + 4.0, "TO PLAY", 9,
			UiChrome.C_DIM, bold)
		return
	UiChrome.text_r(c, rect.end.x - 10.0, line1, "%d" % int(tie.get("home_goals", 0)), 13,
		home_ink, bold)
	UiChrome.text_r(c, rect.end.x - 10.0, line2, "%d" % int(tie.get("away_goals", 0)), 13,
		away_ink, bold)
	var detail := ""
	if int(tie.get("pens_home", -1)) >= 0:
		detail = "PENS %d–%d" % [int(tie.get("pens_home", 0)), int(tie.get("pens_away", 0))]
	elif bool(tie.get("extra_time", false)):
		detail = "AET"
	if detail != "":
		UiChrome.text(c, Vector2(rect.end.x - score_w - 8.0, line2), detail, 9, UiChrome.C_SOFT, med)
	if int(tie.get("legs", 1)) > 1:
		UiChrome.text(c, Vector2(rect.end.x - score_w - 8.0, line1), "AGG", 9, UiChrome.C_DIM, med)

# gd-tools: no cover end
