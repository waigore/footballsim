class_name LeagueStatsSheet
extends RefCounted


const HEADER := LeagueExtra.HEADER
const ROW_H := LeagueExtra.ROW_H
const GAP := LeagueExtra.GAP
const FIELD_H := LeagueExtra.FIELD_H

const STEP_W := 34.0
const STEP_H := 28.0
const STEP_GAP := 4.0
const STEP_AFTER := 24.0

const STAT_W := [72.0, 78.0]
const STAT_GAP := 8.0

var cache := {}

var hints := DateHints.new()


func layout(vp: Vector2, view: Dictionary) -> Array:
	var touch := bool(view.get("touch", false))
	var items: Array = []
	items.append(LeagueExtra.back_item(touch))
	var filters: Dictionary = view.get("filters", {})
	var chip_h: float = UiChrome.tap_h(30.0, touch)
	var step_h: float = UiChrome.tap_h(STEP_H, touch)
	var y := HEADER + 10.0

	var chips: Array = [{"id": "", "short": "ALL"}]
	for comp in view.get("competitions", []):
		chips.append({"id": str(comp["id"]), "short": str(comp.get("short", comp["id"]))})
	var gap := 8.0
	var cw: float = minf(150.0, (vp.x - 48.0 - gap * float(chips.size() - 1)) / float(maxf(chips.size(), 1)))
	var x := 24.0
	for chip in chips:
		items.append({"id": "statsleague:" + str(chip["id"]), "kind": "choice",
			"label": str(chip["short"]), "selected": str(filters.get("league", "")) == str(chip["id"]),
			"rect": Rect2(x, y, cw, chip_h)})
		x += cw + gap
	y += chip_h + 10.0


	var month_label: String = _month_label(str(filters.get("month", "")))
	var step := month_stepper(vp, y, month_label, UiChrome.fonts()["bold"], touch)
	items.append_array(step)
	var stat_x: float = (step[2]["rect"] as Rect2).end.x + STEP_AFTER
	if stat_x + float(STAT_W[0]) + STAT_GAP + float(STAT_W[1]) > vp.x - 24.0:
		y += step_h + 8.0
		stat_x = 24.0

	items.append({"id": "statsstat:goals", "kind": "chip", "label": "GOALS",
		"selected": str(filters.get("stat", "goals")) == "goals",
		"rect": Rect2(stat_x, y, float(STAT_W[0]), step_h)})
	items.append({"id": "statsstat:assists", "kind": "chip", "label": "ASSISTS",
		"selected": str(filters.get("stat", "goals")) == "assists",
		"rect": Rect2(stat_x + float(STAT_W[0]) + STAT_GAP, y, float(STAT_W[1]), step_h)})
	y += step_h + 10.0
	items.append({"id": "statsteam", "kind": "field", "value": str(filters.get("team", "")),
		"rect": Rect2(24.0, y, vp.x - 48.0, FIELD_H)})
	y += FIELD_H + 12.0
	items.append({"id": "stats:reports", "kind": "door", "label": "MATCHDAY REPORTS", "primary": true,
		"rect": Rect2(24.0, y, minf(300.0, vp.x - 48.0), 44.0)})
	if bool(view.get("complete", false)):
		items.append({"id": "stats:podium", "kind": "door", "label": "PODIUM", "primary": false,
			"rect": Rect2(24.0 + minf(300.0, vp.x - 48.0) + 12.0, y, 160.0, 44.0)})
	y += 58.0
	items.append({"id": "", "kind": "caption", "label": "PLAYED MATCHDAYS",
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 26.0
	var reports: Array = view.get("reports", [])
	if reports.is_empty():


		var note: String = "No matchdays match these filters."
		if int(view.get("played", 0)) == 0:
			note = "No matchday has been played yet."
		items.append({"id": "", "kind": "note", "label": note,
			"rect": Rect2(24.0, y, vp.x - 48.0, 24.0)})
	for i in range(reports.size()):
		var row: Dictionary = reports[i]
		items.append({"id": "statsday:" + str(row["date"]), "kind": "day", "row": row,
			"rect": Rect2(24.0, y + float(i) * (ROW_H + GAP), vp.x - 48.0, ROW_H)})
	y += float(reports.size()) * (ROW_H + GAP) + 10.0
	var leaders: Array = view.get("leaders", [])


	if leaders.is_empty():
		return items
	items.append({"id": "", "kind": "caption",
		"label": "LEADERS  ·  %s" % str(filters.get("stat", "goals")).to_upper(),
		"rect": Rect2(24.0, y, vp.x - 48.0, 20.0)})
	y += 24.0
	for i in range(leaders.size()):
		items.append({"id": "", "kind": "leader", "row": leaders[i], "rank": i + 1,
			"rect": Rect2(24.0, y + float(i) * 24.0, vp.x - 48.0, 23.0)})
	return items


static func month_stepper(vp: Vector2, y: float, label: String, bold: Font, touch := false) -> Array:
	var step_w: float = UiChrome.tap_h(STEP_W, touch)
	var step_h: float = UiChrome.tap_h(STEP_H, touch)
	var stat_w: float = float(STAT_W[0]) + STAT_GAP + float(STAT_W[1])
	var room: float = vp.x - 48.0 - step_w * 2.0 - STEP_GAP * 2.0 - STEP_AFTER - stat_w
	var read_w: float = clampf(UiChrome.text_width(bold, label, 10) + 20.0, 72.0, maxf(room, 72.0))
	var prev := Rect2(24.0, y, step_w, step_h)
	var read := Rect2(prev.end.x + STEP_GAP, y, read_w, step_h)
	var next := Rect2(read.end.x + STEP_GAP, y, step_w, step_h)
	return [
		{"id": "statsmonth:-1", "kind": "chip", "label": "<", "rect": prev},
		{"id": "", "kind": "stepper", "label": label, "rect": read},
		{"id": "statsmonth:1", "kind": "chip", "label": ">", "rect": next},
	]


static func _month_label(month: String) -> String:
	if month == "":
		return "ALL MONTHS"
	return LeagueMonth.label(month)

# gd-tools: no cover start

func draw_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "STATS", str(view.get("name", "")), 0.0, true,
		bool(view.get("touch", false)))

func draw_body(c: CanvasItem, _vp: Vector2, fonts: Dictionary, items: Array,
		_view: Dictionary) -> void:
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "door":
			UiChrome.button(c, cache, rect, str(item["label"]), bold, bool(item["primary"]))
		elif kind == "choice" or kind == "chip":
			var on := bool(item.get("selected", false))
			UiChrome.panel(c, cache, rect,
				UiChrome.C_GOLD.darkened(0.1) if on else UiChrome.C_PANEL, 6,
				UiChrome.C_GOLD if on else UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
				str(item["label"]), 10, Color(0.06, 0.06, 0.05) if on else UiChrome.C_SOFT, bold)
		elif kind == "stepper":


			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_BORDER, 1)
			UiChrome.text_c(c, rect.get_center().x, rect.position.y + rect.size.y * 0.5 + 4.0,
				str(item["label"]), 10, UiChrome.C_SOFT, bold)
		elif kind == "field":
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6, UiChrome.C_GOLD, 1)
			var typed := str(item["value"])
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 25.0),
				typed if typed != "" else "FILTER TEAMS (TYPE A CLUB)", 12,
				UiChrome.C_TEXT if typed != "" else UiChrome.C_DIM, bold)
		elif kind == "caption":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 10,
				UiChrome.C_DIM, bold)
		elif kind == "note":
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), str(item["label"]), 11,
				UiChrome.C_SOFT, med)
		elif kind == "day":
			var row: Dictionary = item["row"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 6)
			UiChrome.text(c, Vector2(rect.position.x + 12.0, rect.position.y + 16.0),
				"MATCHDAY %d" % int(row.get("matchday", 1)), 12, UiChrome.C_TEXT, bold)
			UiChrome.text(c, Vector2(rect.position.x + 132.0, rect.position.y + 16.0),
				str(row.get("label", row.get("date", ""))), 10, UiChrome.C_DIM, med)
			var leagues: Array = row.get("leagues", [])
			if not leagues.is_empty():
				UiChrome.text(c, Vector2(rect.position.x + 250.0, rect.position.y + 16.0),
					_league_marks(leagues), 9, UiChrome.C_GOLD, bold)
			UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 16.0,
				"%d RESULTS" % int(row.get("played", 0)), 9, UiChrome.C_GOLD, bold)
		elif kind == "leader":
			var leader: Dictionary = item["row"]
			var rank := int(item["rank"])
			UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 15.0), "%d" % rank, 10,
				UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(rect.position.x + 24.0, rect.position.y + 15.0),
				str(leader.get("name", "")), 11, UiChrome.C_TEXT, bold)
			var club_line := "%s  ·  %s" % [str(leader.get("club_name", leader.get("abbr", ""))),
				_comp_short(str(leader.get("competition_id", "")))]
			var club_x := rect.position.x + 260.0
			var club_room: float = rect.end.x - 10.0 - club_x - 30.0
			UiChrome.text(c, Vector2(club_x, rect.position.y + 15.0),
				LeagueColumns.fit_name(club_line, med, 9, club_room),
				9, UiChrome.C_DIM, med)
			UiChrome.text_r(c, rect.end.x - 10.0, rect.position.y + 15.0,
				str(int(leader.get("stat_value", leader.get("goals", 0)))), 11, UiChrome.C_GOLD, bold)

static func _league_marks(leagues: Array) -> String:
	var out: Array = []
	for cid in leagues:
		out.append(_comp_short(str(cid)))
	return "  ·  ".join(PackedStringArray(out))

static func _comp_short(competition_id: String) -> String:
	var row := PLRepository.shared().competition(competition_id)
	return str(row.get("short_name", competition_id))

# gd-tools: no cover end
