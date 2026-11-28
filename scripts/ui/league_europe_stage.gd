class_name LeagueEuropeStage
extends RefCounted


const HEADER := LeagueChrome.HEADER
const CHIP_H := 24.0
const TAB_H := 24.0
const COL_W := 300.0
const COL_MIN := 256.0
const COL_GAP := 10.0
const TIE_H := 62.0
const TIE_TOUCH_H := 68.0
const ROW_H := 22.0
const ROW_TOUCH_H := 44.0
const NUM_W := 26.0
const NUM_GAP := 2.0
const NUM_COLS := 8

var cache := {}
var hints := DateHints.new()
var names := InterestNames.new()


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var width := vp.x - 48.0
	var items: Array = []
	var y := HEADER + 6.0
	items.append_array(_comps(vp, view, y, touch))
	y += CHIP_H + 6.0
	items.append_array(_tabs(vp, view, y, touch))
	y += TAB_H + 8.0
	var draw_round := str(view.get("draw_round", ""))
	if draw_round != "":
		items.append({"id": "europe:draw:%s:%s" % [str(view.get("comp", "")), draw_round],
			"kind": "chip", "label": "DRAW", "selected": false,
			"rect": Rect2(vp.x - 24.0 - 76.0, y, 76.0, UiChrome.tap_h(CHIP_H, touch))})
		y += UiChrome.tap_h(CHIP_H, touch) + 6.0
	var tab := str(view.get("tab", ""))
	if tab == "table":
		items.append_array(_table(vp, view, y, touch))
	elif tab == "bracket":
		items.append_array(_rounds(vp, view, view.get("bracket", []), "BRACKET", y, touch))
	else:
		items.append_array(_rounds(vp, view, view.get("qualifying", []), "QUALIFYING", y, touch))
	items.append(LeagueExtra.back_item(touch))
	return items


func _comps(vp: Vector2, view: Dictionary, y: float, touch: bool) -> Array:
	var width := vp.x - 48.0
	var comps: Array = view.get("comps", [])
	var out: Array = []
	var count := maxi(comps.size(), 1)
	var gap := 8.0
	var w: float = minf(140.0, (width - gap * float(count - 1)) / float(count))
	for i in range(comps.size()):
		var comp: Dictionary = comps[i]
		out.append({"id": "europe:comp:" + str(comp.get("id", "")), "kind": "chip",
			"label": str(comp.get("short", "")), "selected": str(comp.get("id", "")) == str(view.get("comp", "")),
			"rect": Rect2(24.0 + float(i) * (w + gap), y, w, UiChrome.tap_h(CHIP_H, touch))})
	return out


func _tabs(vp: Vector2, view: Dictionary, y: float, touch: bool) -> Array:
	var width := vp.x - 48.0
	var tabs: Array = view.get("tabs", [])
	var out: Array = []
	var gap := 8.0
	var w: float = minf(160.0, (width - gap * float(maxi(tabs.size() - 1, 1))) / float(maxi(tabs.size(), 1)))
	for i in range(tabs.size()):
		var tab: Dictionary = tabs[i]
		out.append({"id": "europe:tab:" + str(tab.get("id", "")), "kind": "tab",
			"label": str(tab.get("label", "")), "selected": str(tab.get("id", "")) == str(view.get("tab", "")),
			"rect": Rect2(24.0 + float(i) * (w + gap), y, w, UiChrome.tap_h(TAB_H, touch))})
	return out


func _rounds(vp: Vector2, view: Dictionary, rounds: Array, empty_label: String, y: float,
		touch: bool) -> Array:
	var out: Array = []
	var width := vp.x - 48.0
	if rounds.is_empty():
		out.append({"id": "", "kind": "note", "label": "NO %s TIES YET" % empty_label,
			"rect": Rect2(24.0, y, width, 20.0)})
		return out
	var show := rounds
	var selected := ""
	if touch:
		selected = str(view.get("round", ""))
		if not _has_round(rounds, selected):
			selected = str((rounds[0] as Dictionary).get("id", ""))
		var gap := 6.0
		var w: float = minf(120.0, (width - gap * float(maxi(rounds.size() - 1, 1))) / float(maxi(rounds.size(), 1)))
		for i in range(rounds.size()):
			var row: Dictionary = rounds[i]
			out.append({"id": "europe:round:" + str(row.get("id", "")), "kind": "tab",
				"label": LeagueEurope.badge(str(row.get("id", ""))),
				"selected": str(row.get("id", "")) == selected,
				"rect": Rect2(24.0 + float(i) * (w + gap), y, w, UiChrome.tap_h(TAB_H, touch))})
		y += UiChrome.tap_h(TAB_H, touch) + 8.0
		for row in rounds:
			if str(row.get("id", "")) == selected:
				show = [row]
	var col_w: float = minf(vp.x - 48.0, 380.0) if touch \
		else clampf((width - COL_GAP * float(maxi(rounds.size() - 1, 0))) / float(maxi(rounds.size(), 1)), COL_MIN, COL_W)
	var x := 24.0
	for round in show:
		out.append_array(_column(x, y, col_w, round, touch))
		x += col_w + COL_GAP
	return out


static func _has_round(rounds: Array, round_id: String) -> bool:
	for row in rounds:
		if str((row as Dictionary).get("id", "")) == round_id:
			return true
	return false


func _column(x: float, y: float, w: float, round: Dictionary, touch: bool) -> Array:
	var out: Array = []
	out.append({"id": "", "kind": "eu_col", "round": round,
		"rect": Rect2(x, y, w, 20.0)})
	var top := y + 24.0
	var h: float = TIE_TOUCH_H if touch else TIE_H
	for tie in round.get("ties", []):
		var id := ""
		if bool((tie as Dictionary).get("played", false)):
			id = "match:" + str((tie as Dictionary).get("report_leg", ""))
		else:
			id = "fixture:" + str((tie as Dictionary).get("fixture", ""))
		out.append({"id": id, "kind": "eu_tie", "tie": tie,
			"rect": Rect2(x, top, w, h)})
		out.append_array(_names(Rect2(x, top, w, h), tie, touch))
		var badge := LeagueEuropeTies.drop_label(tie.get("drop", {}))
		var target := str((tie.get("drop", {}) as Dictionary).get("to", ""))
		if badge == "":
			badge = LeagueEuropeTies.arrival_label(tie.get("arrival", {}))
			target = str((tie.get("arrival", {}) as Dictionary).get("competition", ""))
		if badge != "" and target != "":
			var bw: float = UiChrome.text_width(UiChrome.fonts()["bold"], badge, 8)
			out.append({"id": "europe:comp:" + target, "kind": "eu_badge",
				"rect": Rect2(x + w - 8.0 - bw, top + h - 16.0, bw, 12.0)})
		top += h + 6.0
	return out


func _names(rect: Rect2, tie: Dictionary, touch: bool) -> Array:
	var out: Array = []
	var line: float = rect.position.y + (18.0 if touch else 16.0)
	var step: float = 20.0 if touch else 16.0
	for side in ["home", "away"]:
		var club := str(tie.get(side, ""))
		if club == "":
			continue
		var name := str(tie.get(side + "_name", club))
		var room: float = rect.size.x - 80.0
		var sized: String = LeagueColumns.fit_name(name, UiChrome.fonts()["bold"], 11, room)
		var w: float = UiChrome.text_width(UiChrome.fonts()["bold"], sized, 11)
		out.append({"id": "club:" + club, "kind": "eu_name", "club": club,
			"rect": Rect2(rect.position.x + 8.0, line - 11.0, w, 13.0)})
		line += step
	return out


func _table(vp: Vector2, view: Dictionary, y: float, touch: bool) -> Array:
	var out: Array = []
	var rows: Array = view.get("table", [])
	var row_w: float = maxf(vp.x - 48.0, 30.0 + 150.0 + float(NUM_COLS) * (NUM_W + NUM_GAP))
	out.append({"id": "", "kind": "eu_legend",
		"rect": Rect2(24.0, y, row_w, 16.0)})
	y += 18.0
	if rows.is_empty():
		out.append({"id": "", "kind": "note",
			"label": "THE LEAGUE PHASE OPENS AFTER THE PLAY-OFF ROUND",
			"rect": Rect2(24.0, y, row_w, 20.0)})
		return out
	out.append({"id": "", "kind": "eu_head", "rect": Rect2(24.0, y, row_w, 18.0)})
	y += 20.0
	var h: float = ROW_TOUCH_H if touch else ROW_H
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var position := int(row.get("position", i + 1))
		out.append({"id": "club:" + str(row.get("club_id", "")), "kind": "eu_row", "row": row,
			"zone": LeagueUefaLeaguePhase.zone(position),
			"interested": interest.has(str(row.get("club_id", ""))),
			"rect": Rect2(24.0, y + float(i) * h, row_w, h - 1.0)})
	return out

# gd-tools: no cover start


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints_out: DateHints) -> void:
	var touch := bool(view.get("touch", false))
	var comp := str(view.get("short", ""))
	var caption := str(view.get("stage", ""))
	LeagueExtra.header(c, vp, fonts, "EUROPE · " + comp, caption, 0.0, true, touch)

func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		match str(item.get("kind", "")):
			"chip":
				var on := bool(item.get("selected", false))
				UiChrome.panel(c, cache, rect, UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL,
					5, UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
				UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
					str(item.get("label", "")), 10,
					Color(0.06, 0.06, 0.05) if on else UiChrome.C_SOFT, bold)
			"tab":
				_tab(c, rect, item, bold)
			"eu_col":
				_col(c, rect, item["round"], bold, med)
			"eu_tie":
				_tie(c, rect, item["tie"], fonts, view)
			"eu_name":
				pass
			"eu_legend":
				_legend(c, rect, bold)
			"eu_head":
				_head(c, rect, bold)
			"eu_row":
				_row(c, rect, item, fonts)
			"note":
				UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
					str(item.get("label", "")), 12, UiChrome.C_SOFT, med)


func _tab(c: CanvasItem, rect: Rect2, item: Dictionary, bold: Font) -> void:
	var on := bool(item.get("selected", false))
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL_LIGHT if on else UiChrome.C_PANEL, 5,
		UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
	UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
		str(item.get("label", "")), 10 if on else 9,
		UiChrome.C_TEXT if on else UiChrome.C_DIM, bold)


func _col(c: CanvasItem, rect: Rect2, round: Dictionary, bold: Font, med: Font) -> void:
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
		str(round.get("title", "")), 10, UiChrome.C_GOLD, bold)
	var date := FixtureCalendar.day_label(str(round.get("date", "")))
	if date != "":
		UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 22.0), date, 8,
			UiChrome.C_DIM, med)


func _tie(c: CanvasItem, rect: Rect2, tie: Dictionary, fonts: Dictionary, view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var touch := bool(view.get("touch", false))
	UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_BORDER, 1)
	var line: float = rect.position.y + (18.0 if touch else 16.0)
	var step: float = 20.0 if touch else 16.0
	for side in ["home", "away"]:
		var club := str(tie.get(side, ""))
		var name := str(tie.get(side + "_name", club))
		var winner := str(tie.get("winner", "")) == club and club != ""
		var ink: Color = UiChrome.C_GOLD if winner else UiChrome.C_TEXT
		var sized: String = LeagueColumns.fit_name(name, bold, 11, rect.size.x - 80.0)
		UiChrome.text(c, Vector2(rect.position.x + 8.0, line), sized, 11, ink, bold)
		line += step
	var bottom := rect.end.y - 8.0
	var legs := _legs(tie)
	var agg := str(tie.get("agg", "—"))
	var status := _status(tie)
	UiChrome.text(c, Vector2(rect.position.x + 8.0, bottom),
		(("AGG " + agg + "  ·  " + legs) if legs != "" else "AGG " + agg), 8,
		UiChrome.C_SOFT, med)
	var badge := LeagueEuropeTies.drop_label(tie.get("drop", {}))
	var badge_ink := UiChrome.C_DANGER
	if badge == "":
		badge = LeagueEuropeTies.arrival_label(tie.get("arrival", {}))
		badge_ink = Color(0.55, 0.72, 0.92)
	if badge != "":
		UiChrome.text_r(c, rect.end.x - 8.0, bottom, badge, 8, badge_ink, bold)
	else:
		UiChrome.text_r(c, rect.end.x - 8.0, bottom, status, 8,
			UiChrome.C_GOLD if status == "▶" else UiChrome.C_DIM, bold)


static func _legs(tie: Dictionary) -> String:
	var parts: Array = []
	for leg in tie.get("legs", []):
		var row: Dictionary = leg
		if not bool(row.get("played", false)):
			continue
		parts.append("%d–%d" % [int(row.get("home_goals", 0)), int(row.get("away_goals", 0))])
	return "  ·  ".join(PackedStringArray(parts))


static func _status(tie: Dictionary) -> String:
	if bool(tie.get("played", false)):
		return "▶"
	return "WATCH" if int(tie.get("watched", 0)) == 1 else "AUTO"


func _legend(c: CanvasItem, rect: Rect2, bold: Font) -> void:
	var parts := [["1–8 R16", "r16"], ["9–24 KO PLAY-OFF", "kopo"], ["25–36 OUT", "out"]]
	var x := rect.position.x
	for part in parts:
		UiChrome.text(c, Vector2(x, rect.position.y + 11.0), str(part[0]), 8,
			LeagueChrome.zone_color(str(part[1])), bold)
		x += UiChrome.text_width(bold, str(part[0]), 8) + 12.0


func _head(c: CanvasItem, rect: Rect2, bold: Font) -> void:
	var places := _places(rect)
	UiChrome.text(c, Vector2(float(places["pos_x"]), rect.position.y + 12.0), "#", 8,
		UiChrome.C_DIM, bold)
	UiChrome.text(c, Vector2(float(places["club_x"]), rect.position.y + 12.0), "CLUB", 8,
		UiChrome.C_DIM, bold)
	for col in places["cols"]:
		UiChrome.text_r(c, float(col["right"]), rect.position.y + 12.0, str(col["label"]), 8,
			UiChrome.C_DIM, bold)


func _row(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var row: Dictionary = item["row"]
	var band := str(item.get("zone", ""))
	c.draw_rect(Rect2(rect.position.x, rect.position.y + 2.0, 3.0, rect.size.y - 4.0),
		LeagueChrome.zone_color(band))
	var places := _places(rect)
	var y := rect.position.y + rect.size.y * 0.5 + 4.0
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	UiChrome.text(c, Vector2(float(places["pos_x"]), y), "%d" % int(row.get("position", 0)), 9,
		UiChrome.C_DIM, med)
	var name: String = LeagueColumns.fit_name(str(row.get("club_name", "")), bold, 11,
		float(places["club_w"]))
	InterestNames.run(c, names, str(row.get("club_id", "")), name,
		Vector2(float(places["club_x"]), y), 11,
		UiChrome.C_GOLD if bool(item.get("interested", false)) else UiChrome.C_TEXT, bold)
	for col in places["cols"]:
		var key := str(col["key"])
		var points := key == "points"
		UiChrome.text_r(c, float(col["right"]), y, _value(row, key), 9 if not points else 10,
			UiChrome.C_TEXT if points else UiChrome.C_SOFT, bold if points else med)


static func _places(rect: Rect2) -> Dictionary:
	var club_x: float = rect.position.x + 30.0
	var club_w: float = maxf(rect.size.x - 30.0 - float(NUM_COLS) * (NUM_W + NUM_GAP), 60.0)
	var out := {"pos_x": rect.position.x + 8.0, "club_x": club_x, "club_w": club_w, "cols": []}
	var x := club_x + club_w
	for label in ["P", "W", "D", "L", "GF", "GA", "GD", "PTS"]:
		out["cols"].append({"key": _key(label), "label": label, "right": x + NUM_W, "w": NUM_W})
		x += NUM_W + NUM_GAP
	return out


static func _key(label: String) -> String:
	match label:
		"P":
			return "played"
		"W":
			return "won"
		"D":
			return "drawn"
		"L":
			return "lost"
		"GF":
			return "gf"
		"GA":
			return "ga"
		"GD":
			return "gd"
	return "points"


static func _value(row: Dictionary, key: String) -> String:
	if key == "gd":
		var gd := int(row.get("gf", 0)) - int(row.get("ga", 0))
		return ("+%d" % gd) if gd > 0 else str(gd)
	return str(int(row.get(key, 0)))

# gd-tools: no cover end
