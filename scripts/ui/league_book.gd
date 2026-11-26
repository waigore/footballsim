class_name LeagueBook
extends RefCounted

## The reading surfaces of a season: the full table with its bands, the month
## calendar and a day's fixtures, match reports and roundups, and the final
## podium. Geometry and paint only — the screen owns the state.
##
## Rows keep a readable height and are allowed to run past the bottom of the
## viewport: LeagueBody clips them and scrolls. Only the bottom doors and the
## month chips are pinned in place.
##
## The month arithmetic (keys, stepping, labels, day counts) lives in
## `LeagueMonth`; this book only places its cells and chips.

const HEADER := LeagueChrome.HEADER
const BAR_H := LeagueChrome.BAR_H

var cache := {}
## Dates this book painted, with the strip each one occupies (#99): the screen's
## overlay paints the weekday for the one under the pointer.
var hints := DateHints.new()
## Club names this book painted, with the strip each one occupies (#107): the
## long press reads it, in the same design space the rows are laid out in.
var names := InterestNames.new()
## The table pose's geometry, sorting and paint (compact/full, header sort), in
## its own module because a table is a reading of its own.
var table := LeagueTableView.new()
## The match report pose, with its own two event columns (#168).
var report_sheet := LeagueReportSheet.new()

func _init() -> void:
	# One registry each, so a long press or a weekday bubble on the report reads
	# the strips the report really painted.
	report_sheet.hints = hints
	report_sheet.names = names

# ----------------------------------------------------------------- table ---

func table_layout(vp: Vector2, view: Dictionary) -> Array:
	return table.layout(vp, view)

## Column geometry for one table row lives in `LeagueTableView`: compact keeps
## `LeagueColumns` (the measured layout #71 settled), the full sheet walks the
## overall, home and away columns from the club's right edge.

func calendar_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	var month := str(view.get("month", ""))
	## The month label and the month chips own the row under the header; the
	## weekday labels start below them so neither is drawn through the other.
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

## The report pose lives in `LeagueReportSheet`: two columns of events under the
## clubs their score line names (#168). Kept behind the same names the screen
## already calls, so the pose table did not change.
func report_layout(vp: Vector2, view: Dictionary) -> Array:
	return report_sheet.layout(vp, view)

func podium_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	## The summary is painted text rather than rows, so a bare extent row carries
	## its height into the scroll window.
	items.append({"id": "", "kind": "extent",
		"rect": Rect2(24.0, HEADER, vp.x - 48.0, frame_height(view))})
	items.append(LeagueExtra.back_item())
	items.append({"id": "table", "kind": "button", "label": "TABLE", "primary": false, "pinned": true,
		"rect": Rect2(24.0, vp.y - BAR_H + 6.0, 130.0, BAR_H - 14.0)})
	items.append({"id": "menu", "kind": "button", "label": "MAIN MENU", "primary": true, "pinned": true,
		"rect": Rect2(24.0 + 142.0, vp.y - BAR_H + 6.0, 170.0, BAR_H - 14.0)})
	return items

## How tall the podium summary paints below the header, so the body can size to
## text that is not made of rows. One block per active competition.
func frame_height(view: Dictionary) -> float:
	var summary: Dictionary = view.get("summary", {})
	if summary.is_empty():
		return 0.0
	var h := 0.0
	for section in _podium_sections(summary):
		var section_rules: Dictionary = section.get("rules", view.get("rules", {}))
		h += 30.0
		h += 18.0 + 44.0 + 24.0 + 16.0
		h += 16.0 * float(mini((section["europe"] as Array).size(), 6))
		h += 6.0 + 16.0
		h += 16.0 * float((section["relegated"] as Array).size())
		# A promoting tier paints its PROMOTED block under the drop.
		var up := int(section_rules.get("promotion_places", 0))
		if up > 0:
			h += 6.0 + 16.0 + 16.0 * float(up)
		h += 12.0
	if not (summary.get("relegation", {}) as Dictionary).is_empty():
		h += 8.0 + 16.0
	return h + 8.0

## The podium's blocks: every active league when the summary carries them, or
## the one league a single-league save mirrors at the top.
static func _podium_sections(summary: Dictionary) -> Array:
	var sections: Array = summary.get("competitions", [])
	if sections.is_empty() and not summary.is_empty():
		sections = [summary]
	return sections

## Paste `body` into the paint path inside the header band. `body` is a bound
## callable — `_draw_calendar_body.bind(vp, fonts, items, view)` — so the first
## painted frame reuses the `_draw` call already entered instead of calling
## `draw_*` (and its measured run) again. The headless suite never paints, so
## this is the only branch there; see docs/testing.md.
func _paint_band(c: CanvasItem, body: Callable) -> void:
	body.call(c)

# gd-tools: no cover start

func draw_table_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	table.draw_chrome(c, vp, fonts, view, hints)

func draw_table_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	table.draw_body(c, vp, fonts, items, view, names)

# -------------------------------------------------------------- calendar ---

func draw_calendar_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "CALENDAR")
	UiChrome.text(c, Vector2(24.0, HEADER + 25.0), LeagueMonth.label(str(view.get("month", ""))),
		13, UiChrome.C_TEXT, fonts["bold"])

func draw_calendar_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	_paint_band(c, _draw_calendar_body.bind(vp, fonts, items, view))

func _draw_calendar_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array,
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
			# A result reads as the same block the hub prints: full names and
			# each side's events under its own name (#168). A pending fixture
			# keeps the calendar's one line with OPEN in the score's place.
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

## True when the day on screen holds more than one competition, which is when
## the calendar groups the list under league headings.
static func _has_many_comps(view: Dictionary) -> bool:
	var seen := {}
	for fx in view.get("day_fixtures", []):
		seen[str(fx.get("competition_id", ""))] = true
	return seen.size() > 1

func _draw_cell(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var info: Dictionary = item["info"]
	var has := int(info.get("n", 0)) > 0
	var selected := bool(item["selected"])
	var fill: Color = UiChrome.C_PANEL_LIGHT if has else UiChrome.C_PANEL
	if selected:
		fill = UiChrome.C_GOLD.darkened(0.25)
	UiChrome.panel(c, cache, rect, fill, 4, UiChrome.C_BORDER, 1)
	# A selected cell is gold, so the sheet's light inks wash out on it: the day
	# and its counter take the dark ink the gold doors and the WATCH chip use
	# (#126). On a dark cell the counter keeps its live/planned colour.
	var ink: Color = Color(0.06, 0.06, 0.05) if selected else (UiChrome.C_TEXT if has else UiChrome.C_DIM)
	UiChrome.text(c, Vector2(rect.position.x + 4.0, rect.position.y + 12.0), "%d" % int(item["day"]), 10,
		ink, fonts["med"])
	if has:
		var done := int(info.get("played", 0))
		var total := int(info.get("n", 0))
		var count_ink: Color = ink if selected else (UiChrome.C_LIVE if done == total else UiChrome.C_GOLD)
		UiChrome.text_r(c, rect.end.x - 3.0, rect.end.y - 4.0, "%d/%d" % [done, total], 10,
			count_ink, fonts["bold"])
		# A mixed day says which league plays: one short mark per competition
		# (P = Premier League, L = La Liga) with its fixture count.
		var by_league: Dictionary = info.get("by_league", {})
		if by_league.size() > 1:
			var mx := rect.position.x + 4.0
			for cid in by_league:
				var short: String = PLRepository.shared().competition_name(str(cid)).substr(0, 1)
				UiChrome.text(c, Vector2(mx, rect.end.y - 4.0),
					"%s%d" % [short, int((by_league[cid] as Dictionary).get("n", 0))], 7,
					ink if selected else UiChrome.C_SOFT, fonts["med"])
				mx += 12.0

# ---------------------------------------------------------------- report ---

func draw_report_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	report_sheet.draw_chrome(c, vp, fonts, view, hints)

func draw_report_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	report_sheet.draw_body(c, vp, fonts, items, view)

# ---------------------------------------------------------------- podium ---

func draw_podium_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "SEASON COMPLETE", str(view.get("name", "")))

func draw_podium_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, _items: Array, view: Dictionary) -> void:
	_paint_band(c, _draw_podium_body.bind(vp, fonts, view))

func _draw_podium_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var summary: Dictionary = view.get("summary", {})
	var y := HEADER + 6.0
	if summary.is_empty():
		return
	for section in _podium_sections(summary):
		var section_rules: Dictionary = section.get("rules", view.get("rules", {}))
		UiChrome.text(c, Vector2(24.0, y + 12.0), str(section.get("name", section.get("short", ""))).to_upper(),
			12, UiChrome.C_GOLD, bold)
		c.draw_rect(Rect2(24.0, y + 18.0, vp.x - 48.0, 1.0), Color(1, 1, 1, 0.10))
		y += 30.0
		UiChrome.text(c, Vector2(24.0, y), "CHAMPIONS", 10, UiChrome.C_DIM, bold)
		UiChrome.text(c, Vector2(24.0, y + 30.0), str(section["champion"]["club"]), 30, UiChrome.C_GOLD, bold)
		UiChrome.text_r(c, vp.x - 24.0, y + 30.0, "%d PTS" % int(section["champion"]["points"]),
			14, UiChrome.C_TEXT, bold)
		y += 44.0
		UiChrome.text(c, Vector2(24.0, y), "RUNNER-UP  %s · %d PTS" % [str(section["runner_up"]["club"]),
			int(section["runner_up"]["points"])], 12, UiChrome.C_SOFT, bold)
		y += 24.0
		# A second tier has no European places; its band is promotion (#240).
		var section_up := int(section_rules.get("promotion_places", 0))
		if (section["europe"] as Array).is_empty() and section_up > 0:
			_paint_promoted(c, vp, section, section_up, y, bold, med)
			y += 16.0 + 16.0 * float(section_up)
		else:
			UiChrome.text(c, Vector2(24.0, y), "EUROPEAN PLACES", 10, UiChrome.C_DIM, bold)
			y += 16.0
			var zone_rows: Array = section["europe"]
			for i in range(mini(zone_rows.size(), 6)):
				var row: Dictionary = zone_rows[i]
				var club := _club_row(section, str(row["zone"]))
				var band := LeagueRules.zone(int(row["position"]), section_rules)
				c.draw_rect(Rect2(24.0, y + 2.0, 3.0, 12.0), LeagueChrome.zone_color(band))
				UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
				UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_TEXT, med)
				UiChrome.text_r(c, vp.x - 24.0, y + 12.0, str(club.get("points", "")), 10, UiChrome.C_SOFT, bold)
				y += 16.0
		y += 6.0
		UiChrome.text(c, Vector2(24.0, y), "RELEGATED", 10, UiChrome.C_DIM, bold)
		y += 16.0
		for row in section["relegated"]:
			UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_DANGER, med)
			y += 16.0
		var scorers: Array = section.get("top_scorers", [])
		if not scorers.is_empty():
			UiChrome.text_r(c, vp.x - 24.0, y + 12.0, "TOP SCORER  %s (%d)" % [str(scorers[0]["name"]),
				int(scorers[0]["goals"])], 11, UiChrome.C_SOFT, bold)
		y += 12.0
	# One Relegation block under both tiers: the tie is one match, not a row of
	# either league's podium.
	var tie: Dictionary = summary.get("relegation", {})
	if not tie.is_empty():
		UiChrome.text(c, Vector2(24.0, y + 8.0), "RELEGATION  %s" % str(tie.get("text", "")),
			10, UiChrome.C_GOLD, bold)
		y += 16.0

## The promoting side of the graph: a second tier's top places, with the
## Relegation third marked as the playoff rather than a European band.
func _paint_promoted(c: CanvasItem, vp: Vector2, section: Dictionary, up: int,
		y: float, bold: Font, med: Font) -> void:
	UiChrome.text(c, Vector2(24.0, y), "PROMOTION", 10, UiChrome.C_DIM, bold)
	var rows: Array = section.get("table", [])
	for i in range(mini(up + int((section.get("rules", {}) as Dictionary)
			.get("promotion_playoff_places", 0)), rows.size())):
		var row: Dictionary = rows[i]
		var band := "promotion" if i < up else "playoff"
		var cy := y + 16.0 + 16.0 * float(i)
		c.draw_rect(Rect2(24.0, cy + 2.0, 3.0, 12.0), LeagueChrome.zone_color(band))
		UiChrome.text(c, Vector2(32.0, cy + 12.0), "%d" % (i + 1), 10, UiChrome.C_DIM, med)
		UiChrome.text(c, Vector2(54.0, cy + 12.0), str(row.get("club_name", "")), 11, UiChrome.C_TEXT, med)
		UiChrome.text_r(c, vp.x - 24.0, cy + 12.0, str(row.get("points", "")), 10, UiChrome.C_SOFT, bold)

func _club_row(section: Dictionary, club_id: String) -> Dictionary:
	for row in section.get("table", []):
		if str(row["club_id"]) == club_id:
			return row
	return {}

# gd-tools: no cover end
