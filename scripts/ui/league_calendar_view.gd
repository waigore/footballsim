class_name LeagueCalendarView
extends RefCounted


const HEADER := LeagueChrome.HEADER

const COMPACT_H := 620.0

const CELL_H := 30.0
const CELL_H_TALL := 34.0

const CELL_GAP := 2.0

const LEGEND := "FIXTURES PLAYED / TOTAL"

const LEGEND_SHORT := "PLAYED / TOTAL"

const LEGEND_SIZE := 10


static func cell_pitch(vp: Vector2, touch: bool) -> float:
	var base: float = CELL_H if vp.y < COMPACT_H else CELL_H_TALL
	return maxf(base, UiChrome.TAP_H + CELL_GAP) if touch else base


static func has_filters(view: Dictionary) -> bool:
	return (view.get("filters", []) as Array).size() > 1


static func chips_top(touch: bool) -> float:
	return HEADER + (4.0 + UiChrome.TAP_H + 6.0 if touch else 38.0)


static func chip_h(touch: bool) -> float:
	return UiChrome.tap_h(22.0, touch)


static func chip_rects(vp: Vector2, view: Dictionary) -> Array:
	var filters: Array = view.get("filters", [])
	var touch := bool(view.get("touch", false))
	var out: Array = []
	if filters.size() <= 1:
		return out
	var gap := 6.0
	var w: float = minf(96.0,
		(vp.x - 48.0 - gap * float(filters.size() - 1)) / float(filters.size()))
	for i in range(filters.size()):
		var row: Dictionary = filters[i]
		out.append({"id": "cal:" + str(row.get("id", "")), "kind": "cal_chip",
			"label": str(row.get("label", "")), "selected": bool(row.get("selected", false)),
			"rect": Rect2(24.0 + float(i) * (w + gap), chips_top(touch), w, chip_h(touch))})
	return out


static func grid_top(touch: bool, filters: bool = false) -> float:
	var out: float = HEADER + 4.0 + UiChrome.TAP_H + 20.0 if touch else HEADER + 50.0
	if filters:
		out = maxf(out, chips_top(touch) + chip_h(touch) + 10.0)
	return out


static func month_door_rects(vp: Vector2, touch: bool) -> Array:
	if touch:
		var w: float = UiChrome.TAP_H
		return [Rect2(vp.x - 24.0 - w * 2.0 - 8.0, HEADER + 4.0, w, w),
			Rect2(vp.x - 24.0 - w, HEADER + 4.0, w, w)]
	return [Rect2(vp.x - 24.0 - 132.0, HEADER + 8.0, 28.0, 24.0),
		Rect2(vp.x - 24.0 - 28.0, HEADER + 8.0, 28.0, 24.0)]

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()


static func legend_rect(vp: Vector2, view: Dictionary, fonts: Dictionary) -> Dictionary:
	if not _month_has_fixtures(view):
		return {}
	var bold: Font = fonts["bold"]
	var label: String = LeagueMonth.label(str(view.get("month", "")))
	var left: float = 24.0 + UiChrome.text_width(bold, label, 13) + 12.0
	var right: float = month_door_rects(vp, bool(view.get("touch", false)))[0].position.x - 12.0
	var room: float = right - left
	for text in [LEGEND, LEGEND_SHORT]:
		var width: float = UiChrome.text_width(bold, str(text), LEGEND_SIZE)
		if width <= room:
			return {"text": str(text), "rect": Rect2(left, HEADER + 13.0, width, 12.0)}
	return {}


static func _month_has_fixtures(view: Dictionary) -> bool:
	var days: Dictionary = view.get("days", {})
	for date in days:
		if int((days[date] as Dictionary).get("n", 0)) > 0:
			return true
	return false

func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	var month := str(view.get("month", ""))


	var filtered := has_filters(view)
	for chip in chip_rects(vp, view):
		items.append(chip)
	var top := grid_top(touch, filtered)
	var cw := (vp.x - 48.0) / 7.0
	var ch: float = cell_pitch(vp, touch)
	var count := LeagueMonth.days(month)
	var first := LeagueMonth.first_weekday(month)
	for i in range(count):
		var slot := first + i
		var col := slot % 7
		var row := slot / 7
		var date := "%s-%02d" % [month, i + 1]
		var info: Dictionary = (view.get("days", {}) as Dictionary).get(date, {})
		items.append({
			"id": "day:" + date, "kind": "cell", "date": date, "day": i + 1,
			"info": info, "selected": str(view.get("day", "")) == date,
			"rect": Rect2(24.0 + float(col) * cw, top + float(row) * ch, cw - 2.0, ch - 2.0),
		})
	var y := top + 6.0 * ch + 10.0
	var last_comp := ""
	for fx in view.get("day_fixtures", []):
		var comp := str(fx.get("competition_id", ""))
		var heading := comp != last_comp and (_has_many_comps(view)
			or LeagueUefa.is_continental(comp))
		if heading:
			last_comp = comp
			items.append({"id": "", "kind": "league_head", "competition": comp,
				"matchday": int(fx.get("matchday", 1)),
				"rect": Rect2(24.0, y, vp.x - 48.0, 16.0)})
			y += 18.0
		var h: float = maxf(22.0, LeagueBlock.height(fx, true))
		items.append({"id": "match:" + str(fx["id"]), "kind": "fixture",
			"fixture": fx, "rect": Rect2(24.0, y, vp.x - 48.0, h)})
		y += h + 2.0
	var doors := month_door_rects(vp, touch)
	items.append({"id": "month:-1", "kind": "chip", "label": "<", "pinned": true, "rect": doors[0]})
	items.append({"id": "month:1", "kind": "chip", "label": ">", "pinned": true, "rect": doors[1]})
	items.append(LeagueExtra.back_item(touch))
	return items


static func _has_many_comps(view: Dictionary) -> bool:
	var seen := {}
	for fx in view.get("day_fixtures", []):
		seen[str(fx.get("competition_id", ""))] = true
	return seen.size() > 1


func _paint_band(c: CanvasItem, body: Callable) -> void:
	body.call(c)

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "CALENDAR", "", 0.0, true,
		bool(view.get("touch", false)))
	UiChrome.text(c, Vector2(24.0, HEADER + 25.0), LeagueMonth.label(str(view.get("month", ""))),
		13, UiChrome.C_TEXT, fonts["bold"])
	var legend := legend_rect(vp, view, fonts)
	if not legend.is_empty():
		var rect: Rect2 = legend["rect"]
		UiChrome.text(c, Vector2(rect.position.x, rect.end.y), str(legend["text"]),
			LEGEND_SIZE, UiChrome.C_DIM, fonts["bold"])

func draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	_paint_band(c, _draw_body.bind(vp, fonts, items, view))

func _draw_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
		view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var labels := ["S", "M", "T", "W", "T", "F", "S"]
	var rows_y: float = grid_top(bool(view.get("touch", false)), has_filters(view)) - 8.0
	for i in range(7):
		var cw := (vp.x - 48.0) / 7.0
		UiChrome.text_c(c, 24.0 + cw * float(i) + cw * 0.5, rows_y, labels[i], 10, UiChrome.C_DIM, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "cell":
			_draw_cell(c, rect, item, fonts)
		elif kind == "cal_chip":
			var on := bool(item.get("selected", false))
			UiChrome.panel(c, cache, rect, UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL,
				4, UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
				str(item.get("label", "")), 9,
				Color(0.06, 0.06, 0.05) if on else UiChrome.C_SOFT, bold)
		elif kind == "league_head":
			var comp := str(item.get("competition", ""))
			var name: String = PLRepository.shared().competition_name(comp)
			var text := "%s  ·  GW %d" % [name, int(item.get("matchday", 1))]
			if LeagueUefa.is_continental(comp):
				text = "UEFA NIGHT  ·  " + name
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
				text, 9, UiChrome.C_GOLD, bold)
		elif kind == "fixture":


			var fx: Dictionary = item["fixture"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 4)
			var home_id := str(fx.get("home_club_id", ""))
			var away_id := str(fx.get("away_club_id", ""))
			var home_ink := LeagueInterestMark.ink(interest, home_id)
			var away_ink := LeagueInterestMark.ink(interest, away_id)
			if str(fx.get("status", "")) == "played":
				LeagueBlock.paint(c, rect, fx, fonts, names, home_ink, away_ink, true)
				continue
			var fy := rect.position.y + 15.0
			var fx_x := rect.position.x + 8.0
			var kick := str(fx.get("kickoff_time", ""))
			UiChrome.text(c, Vector2(fx_x, fy), kick, 10, UiChrome.C_DIM, med)
			fx_x += InterestNames.width(med, kick, 10) + 8.0
			var room := maxf((rect.end.x - 60.0 - fx_x) * 0.46, 50.0)
			var home_name: String = LeagueColumns.fit_name(str(fx.get("home_name", "")), med,
				11, room)
			fx_x += InterestNames.run(c, names, home_id, home_name, Vector2(fx_x, fy),
				11, home_ink, med) + 5.0
			UiChrome.text(c, Vector2(fx_x, fy), "v", 10, UiChrome.C_DIM, med)
			fx_x += InterestNames.width(med, "v", 10) + 6.0
			var away_name: String = LeagueColumns.fit_name(str(fx.get("away_name", "")), med,
				11, maxf(rect.end.x - 60.0 - fx_x, 50.0))
			InterestNames.run(c, names, away_id, away_name, Vector2(fx_x, fy), 11,
				away_ink, med)
			UiChrome.text_r(c, rect.end.x - 8.0, rect.position.y + 15.0, "OPEN", 10,
				UiChrome.C_GOLD, bold)

func _draw_cell(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var info: Dictionary = item["info"]
	var has := int(info.get("n", 0)) > 0
	var selected := bool(item["selected"])
	var fill: Color = UiChrome.C_PANEL_LIGHT if has else UiChrome.C_PANEL
	if selected:
		fill = UiChrome.C_GOLD.darkened(0.25)
	UiChrome.panel(c, cache, rect, fill, 4, UiChrome.C_BORDER, 1)


	var ink: Color = Color(0.06, 0.06, 0.05) if selected else (UiChrome.C_TEXT if has else UiChrome.C_DIM)
	UiChrome.text(c, Vector2(rect.position.x + 4.0, rect.position.y + 12.0), "%d" % int(item["day"]), 10,
		ink, fonts["med"])
	if has:
		var done := int(info.get("played", 0))
		var total := int(info.get("n", 0))
		var count_ink: Color = ink if selected else (UiChrome.C_LIVE if done == total else UiChrome.C_GOLD)
		UiChrome.text_r(c, rect.end.x - 3.0, rect.end.y - 4.0, "%d/%d" % [done, total], 10,
			count_ink, fonts["bold"])


		var by_league: Dictionary = info.get("by_league", {})
		if by_league.size() > 1:
			var mx := rect.position.x + 4.0
			for cid in by_league:
				var short: String = PLRepository.shared().competition_name(str(cid)).substr(0, 1)
				UiChrome.text(c, Vector2(mx, rect.end.y - 4.0),
					"%s%d" % [short, int((by_league[cid] as Dictionary).get("n", 0))], 7,
					ink if selected else UiChrome.C_SOFT, fonts["med"])
				mx += 12.0

# gd-tools: no cover end
