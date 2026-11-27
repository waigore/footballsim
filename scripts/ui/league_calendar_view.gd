class_name LeagueCalendarView
extends RefCounted


const HEADER := LeagueChrome.HEADER

var cache := {}

var hints := DateHints.new()

var names := InterestNames.new()

func layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var month := str(view.get("month", ""))


	var grid_top := HEADER + 50.0
	var cw := (vp.x - 48.0) / 7.0
	var ch: float = 30.0 if vp.y < 620.0 else 34.0
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
			"rect": Rect2(24.0 + float(col) * cw, grid_top + float(row) * ch, cw - 2.0, ch - 2.0),
		})
	var y := grid_top + 6.0 * ch + 10.0
	var last_comp := ""
	for fx in view.get("day_fixtures", []):
		var comp := str(fx.get("competition_id", ""))
		if comp != last_comp and int((view.get("day_fixtures", []) as Array).size()) > 0:
			last_comp = comp
			if _has_many_comps(view):
				items.append({"id": "", "kind": "league_head", "competition": comp,
					"matchday": int(fx.get("matchday", 1)),
					"rect": Rect2(24.0, y, vp.x - 48.0, 16.0)})
				y += 18.0
		var h: float = maxf(22.0, LeagueBlock.height(fx, true))
		items.append({"id": "match:" + str(fx["id"]), "kind": "fixture",
			"fixture": fx, "rect": Rect2(24.0, y, vp.x - 48.0, h)})
		y += h + 2.0
	items.append({"id": "month:-1", "kind": "chip", "label": "<", "pinned": true,
		"rect": Rect2(vp.x - 24.0 - 132.0, HEADER + 8.0, 28.0, 24.0)})
	items.append({"id": "month:1", "kind": "chip", "label": ">", "pinned": true,
		"rect": Rect2(vp.x - 24.0 - 28.0, HEADER + 8.0, 28.0, 24.0)})
	items.append(LeagueExtra.back_item())
	return items


static func _has_many_comps(view: Dictionary) -> bool:
	var seen := {}
	for fx in view.get("day_fixtures", []):
		seen[str(fx.get("competition_id", ""))] = true
	return seen.size() > 1


func _paint_band(c: CanvasItem, body: Callable) -> void:
	body.call(c)


func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "CALENDAR")
	UiChrome.text(c, Vector2(24.0, HEADER + 25.0), LeagueMonth.label(str(view.get("month", ""))),
		13, UiChrome.C_TEXT, fonts["bold"])

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
	for i in range(7):
		var cw := (vp.x - 48.0) / 7.0
		UiChrome.text_c(c, 24.0 + cw * float(i) + cw * 0.5, HEADER + 42.0, labels[i], 10, UiChrome.C_DIM, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "cell":
			_draw_cell(c, rect, item, fonts)
		elif kind == "league_head":
			var name: String = PLRepository.shared().competition_name(str(item.get("competition", "")))
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 12.0),
				"%s  ·  GW %d" % [name, int(item.get("matchday", 1))], 9, UiChrome.C_GOLD, bold)
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


