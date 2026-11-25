class_name LeagueBook
extends RefCounted

## The reading surfaces of a season: the full table with its bands, the month
## calendar and a day's fixtures, match reports and roundups, and the final
## podium. Geometry and paint only — the screen owns the state.
##
## Rows keep a readable height and are allowed to run past the bottom of the
## viewport: LeagueBody clips them and scrolls. Only the bottom doors and the
## month chips are pinned in place.

const HEADER := 58.0
const BAR_H := 52.0
## The ▶ hit target beside a goal: thumb-sized, never hover-only.
const PLAY_W := 44.0
const PLAY_H := 26.0
const MONTHS := ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY",
	"AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

var cache := {}
## Dates this book painted, with the strip each one occupies (#99): the screen's
## overlay paints the weekday for the one under the pointer.
var hints := DateHints.new()
## Club names this book painted, with the strip each one occupies (#107): the
## long press reads it, in the same design space the rows are laid out in.
var names := InterestNames.new()
## The table pose's geometry, sorting and paint (compact/full, header sort). It
## lives in its own module because the book is at its method budget.
var table := LeagueTableView.new()

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
	var count := month_days(month)
	var first := _first_weekday(month)
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
	for fx in view.get("day_fixtures", []):
		items.append({"id": "match:" + str(fx["id"]), "kind": "fixture",
			"fixture": fx, "rect": Rect2(24.0, y, vp.x - 48.0, 22.0)})
		y += 23.0
	items.append({"id": "month:-1", "kind": "chip", "label": "<", "pinned": true,
		"rect": Rect2(vp.x - 24.0 - 132.0, HEADER + 8.0, 28.0, 24.0)})
	items.append({"id": "month:1", "kind": "chip", "label": ">", "pinned": true,
		"rect": Rect2(vp.x - 24.0 - 28.0, HEADER + 8.0, 28.0, 24.0)})
	items.append(LeagueExtra.back_item())
	return items

func report_layout(vp: Vector2, view: Dictionary) -> Array:
	var items: Array = []
	# BACK keeps the league's header position, never a bottom door (#105, #162).
	items.append(LeagueExtra.back_item())
	var y := HEADER + 70.0
	var clips := {}
	for row in view.get("highlights", []):
		clips[int(row.get("goal_index", -1))] = row
	var goal := 0
	for e in view.get("events", []):
		var is_goal := str(e.get("kind", "")) == "goal"
		var clip: Dictionary = clips.get(goal, {}) if is_goal else {}
		var index := goal
		if is_goal:
			goal += 1
		var h := 40.0 if not clip.is_empty() else 20.0
		items.append({"id": "", "kind": "event", "event": e, "clip": clip,
			"rect": Rect2(24.0, y, vp.x - 48.0, h)})
		if not clip.is_empty():
			# ▶ is a real touch target beside the goal, never a hover-only door.
			items.append({"id": "goal:%d" % index, "kind": "play", "clip": clip,
				"rect": Rect2(vp.x - 24.0 - PLAY_W, y + 1.0, PLAY_W, PLAY_H)})
		y += h + 1.0
	for report in view.get("roundup", []):
		items.append({"id": "match:" + str(report["fixture"]["id"]), "kind": "result",
			"report": report, "rect": Rect2(24.0, y, vp.x - 48.0, 44.0)})
		y += 50.0
	return items

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
## text that is not made of rows.
func frame_height(view: Dictionary) -> float:
	var summary: Dictionary = view.get("summary", {})
	if summary.is_empty():
		return 0.0
	var h := 18.0 + 44.0 + 24.0 + 16.0
	h += 16.0 * float(mini((summary["europe"] as Array).size(), 6))
	h += 6.0 + 16.0
	h += 16.0 * float((summary["relegated"] as Array).size())
	return h + 8.0

## "2026-08" -> [year, month]; a missing month falls back to today.

static func parse_month(month: String) -> Array:
	if month.length() == 7 and month.substr(4, 1) == "-":
		return [int(month.substr(0, 4)), int(month.substr(5, 2))]
	var now := Time.get_date_dict_from_system()
	return [int(now["year"]), int(now["month"])]

static func month_key(year: int, month: int) -> String:
	var m := ((month - 1) % 12 + 12) % 12 + 1
	var y := year + int(floor(float(month - 1) / 12.0))
	return "%04d-%02d" % [y, m]

static func shift_month(month: String, delta: int) -> String:
	var bits := parse_month(month)
	return month_key(int(bits[0]), int(bits[1]) + delta)

static func month_label(month: String) -> String:
	var bits := parse_month(month)
	return "%s %d" % [MONTHS[int(bits[1]) - 1], int(bits[0])]

static func month_days(month: String) -> int:
	var bits := parse_month(month)
	return _days_in_month(int(bits[0]), int(bits[1]))

## The season clock's month, or the month the screen last showed when there is
## no season loaded.
static func state_month(season, fallback: String) -> String:
	if season == null:
		return fallback
	var date := str(season.state().get("date", ""))
	return date.substr(0, 7) if date.length() >= 7 else fallback

static func _days_in_month(year: int, month: int) -> int:
	var next := month_key(year, month + 1)
	var stamp := Time.get_unix_time_from_datetime_string(next + "-01T00:00:00") - 86400
	return int(Time.get_datetime_dict_from_unix_time(stamp)["day"])

static func _first_weekday(month: String) -> int:
	var stamp := Time.get_unix_time_from_datetime_string(month + "-01T00:00:00")
	return int(Time.get_datetime_dict_from_unix_time(stamp)["weekday"])

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
	UiChrome.text(c, Vector2(24.0, HEADER + 25.0), month_label(str(view.get("month", ""))), 13, UiChrome.C_TEXT, fonts["bold"])

func draw_calendar_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
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
		elif kind == "fixture":
			# Each club is its own run so the long press can name the one under
			# the finger, and a followed club's abbreviation is gold (#107).
			var fx: Dictionary = item["fixture"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 4)
			var fy := rect.position.y + 15.0
			var fx_x := rect.position.x + 8.0
			var kick := str(fx["kickoff_time"])
			UiChrome.text(c, Vector2(fx_x, fy), kick, 10, UiChrome.C_DIM, med)
			fx_x += InterestNames.width(med, kick, 10) + 8.0
			var home_id := str(fx.get("home_club_id", ""))
			var away_id := str(fx.get("away_club_id", ""))
			fx_x += InterestNames.run(c, names, home_id, str(fx["home_abbr"]),
				Vector2(fx_x, fy), 11, LeagueInterestMark.ink(interest, home_id), med) + 5.0
			UiChrome.text(c, Vector2(fx_x, fy), "v", 10, UiChrome.C_DIM, med)
			fx_x += InterestNames.width(med, "v", 10) + 6.0
			InterestNames.run(c, names, away_id, str(fx["away_abbr"]), Vector2(fx_x, fy), 11,
				LeagueInterestMark.ink(interest, away_id), med)
			var score := "%d-%d" % [int(fx["home_goals"]), int(fx["away_goals"])]
			UiChrome.text_r(c, rect.end.x - 8.0, rect.position.y + 15.0,
				score if str(fx["status"]) == "played" else "OPEN", 10,
				UiChrome.C_TEXT if str(fx["status"]) == "played" else UiChrome.C_GOLD, bold)

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

# ---------------------------------------------------------------- report ---

func draw_report_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		hints: DateHints) -> void:
	var bold: Font = fonts["bold"]
	var roundup: Array = view.get("roundup", [])
	var date := str(view.get("day", ""))
	var label := FixtureCalendar.day_label(date)
	var kicker := "MATCH REPORT"
	var caption := ""
	if not roundup.is_empty():
		kicker = "RESULTS"
		caption = label if label != "" else date
	LeagueExtra.header(c, vp, fonts, kicker, caption)
	if caption != "":
		hints.add(DateHints.strip_right(bold, caption, vp.x - 24.0, 34.0, 10), date)

func draw_report_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, items: Array, view: Dictionary) -> void:
	hints.clear()
	names.clear()
	var interest := LeagueInterestMark.set_of(view.get("interests", []))
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	if (view.get("roundup", []) as Array).is_empty():
		var fx: Dictionary = view.get("fixture", {})
		# The headline is three runs so each club name is its own long-press
		# target, and a followed club prints gold like it does in the lists.
		var head_y := HEADER + 34.0
		var home_id := str(fx.get("home_club_id", ""))
		var away_id := str(fx.get("away_club_id", ""))
		var hx := 24.0
		hx += InterestNames.run(c, names, home_id, str(fx.get("home_name", "")),
			Vector2(hx, head_y), 22, LeagueInterestMark.ink(interest, home_id), bold) + 10.0
		var line := "%d – %d" % [int(fx.get("home_goals", 0)), int(fx.get("away_goals", 0))]
		UiChrome.text(c, Vector2(hx, head_y), line, 22, UiChrome.C_TEXT, bold)
		hx += InterestNames.width(bold, line, 22) + 10.0
		InterestNames.run(c, names, away_id, str(fx.get("away_name", "")),
			Vector2(hx, head_y), 22, LeagueInterestMark.ink(interest, away_id), bold)
		var date := str(view.get("day", ""))
		var label := FixtureCalendar.day_label(date)
		UiChrome.text(c, Vector2(24.0, HEADER + 54.0), label, 10, UiChrome.C_DIM, med)
		if date != "":
			hints.add(DateHints.strip(med, label, Vector2(24.0, HEADER + 54.0), 10), date)
		if (view.get("events", []) as Array).is_empty():
			UiChrome.text(c, Vector2(24.0, HEADER + 84.0), "No goals or cards.", 11, UiChrome.C_DIM, med)
	for item in items:
		var rect: Rect2 = item["rect"]
		var kind := str(item["kind"])
		if kind == "event":
			_draw_event(c, rect, item, fonts)
		elif kind == "play":
			LeagueSheet.draw_play(c, cache, rect, fonts["bold"])
		elif kind == "result":
			var report: Dictionary = item["report"]
			var fx: Dictionary = report["fixture"]
			UiChrome.panel(c, cache, rect, UiChrome.C_PANEL, 5)
			var ry := rect.position.y + 18.0
			var rx := rect.position.x + 10.0
			var row_home := str(fx.get("home_club_id", ""))
			var row_away := str(fx.get("away_club_id", ""))
			var score := "%d – %d" % [int(fx["home_goals"]), int(fx["away_goals"])]
			rx += InterestNames.run(c, names, row_home, str(fx["home_abbr"]),
				Vector2(rx, ry), 15, LeagueInterestMark.ink(interest, row_home), bold) + 8.0
			UiChrome.text(c, Vector2(rx, ry), score, 15, UiChrome.C_TEXT, bold)
			rx += InterestNames.width(bold, score, 15) + 8.0
			InterestNames.run(c, names, row_away, str(fx["away_abbr"]), Vector2(rx, ry), 15,
				LeagueInterestMark.ink(interest, row_away), bold)
			# Every scorer says which club scored (DR-20261125-07): the run mixes
			# both sides, so the entry carries its own club label.
			var scorers := LeagueRoundup.run(report, med, rect.size.x - 20.0, 10)
			UiChrome.text(c, Vector2(rect.position.x + 10.0, rect.position.y + 34.0),
				scorers if scorers != "" else LeagueRoundup.NONE, 10, UiChrome.C_DIM, med)

func _draw_event(c: CanvasItem, rect: Rect2, item: Dictionary, fonts: Dictionary) -> void:
	var e: Dictionary = item["event"]
	var kind := str(e.get("kind", ""))
	var colour := UiChrome.C_TEXT
	if kind == "goal":
		colour = UiChrome.C_GOLD
	elif kind == "yellow":
		colour = Color(0.92, 0.84, 0.35)
	elif kind == "red":
		colour = UiChrome.C_DANGER
	elif kind == "injury":
		colour = UiChrome.C_SOFT
	elif kind == "assist":
		colour = UiChrome.C_SOFT
	var name := str(e.get("player_name", e.get("detail", "")))
	UiChrome.text(c, Vector2(rect.position.x, rect.position.y + 14.0), "%d'" % int(e.get("minute", 0)), 10,
		UiChrome.C_DIM, fonts["bold"])
	UiChrome.text(c, Vector2(rect.position.x + 34.0, rect.position.y + 14.0), name, 11, colour, fonts["bold"])
	UiChrome.text(c, Vector2(rect.position.x + 210.0, rect.position.y + 14.0), kind.to_upper(), 10, colour, fonts["med"])
	# A goal with a stored clip reads as a broadcast moment: the commentary line
	# sits under it and the ▶ beside it plays exactly that goal.
	var clip: Dictionary = item.get("clip", {})
	if not clip.is_empty():
		var line := str(clip.get("commentary", ""))
		if line != "":
			var room := maxi(int((rect.size.x - 90.0) / 5.4), 12)
			UiChrome.text(c, Vector2(rect.position.x + 34.0, rect.position.y + 32.0),
				line.substr(0, room), 10, UiChrome.C_SOFT, fonts["med"])

# ---------------------------------------------------------------- podium ---

func draw_podium_chrome(c: CanvasItem, vp: Vector2, fonts: Dictionary, view: Dictionary,
		_hints: DateHints) -> void:
	LeagueExtra.header(c, vp, fonts, "SEASON COMPLETE", str(view.get("name", "")))

func draw_podium_body(c: CanvasItem, vp: Vector2, fonts: Dictionary, _items: Array, view: Dictionary) -> void:
	hints.clear()
	var bold: Font = fonts["bold"]
	var med: Font = fonts["med"]
	var summary: Dictionary = view.get("summary", {})
	var y := HEADER + 18.0
	if not summary.is_empty():
		UiChrome.text(c, Vector2(24.0, y), "CHAMPIONS", 10, UiChrome.C_DIM, bold)
		UiChrome.text(c, Vector2(24.0, y + 30.0), str(summary["champion"]["club"]), 30, UiChrome.C_GOLD, bold)
		UiChrome.text_r(c, vp.x - 24.0, y + 30.0, "%d PTS" % int(summary["champion"]["points"]), 14, UiChrome.C_TEXT, bold)
		y += 44.0
		UiChrome.text(c, Vector2(24.0, y), "RUNNER-UP  %s · %d PTS" % [str(summary["runner_up"]["club"]),
			int(summary["runner_up"]["points"])], 12, UiChrome.C_SOFT, bold)
		y += 24.0
		UiChrome.text(c, Vector2(24.0, y), "EUROPEAN PLACES", 10, UiChrome.C_DIM, bold)
		y += 16.0
		var zone_rows: Array = summary["europe"]
		for i in range(mini(zone_rows.size(), 6)):
			var row: Dictionary = zone_rows[i]
			var club := _club_row(view, str(row["zone"]))
			var band := LeagueRules.zone(int(row["position"]), view.get("rules", {}))
			c.draw_rect(Rect2(24.0, y + 2.0, 3.0, 12.0), LeagueSheet.zone_color(band))
			UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_TEXT, med)
			UiChrome.text_r(c, vp.x - 24.0, y + 12.0, str(club.get("points", "")), 10, UiChrome.C_SOFT, bold)
			y += 16.0
		y += 6.0
		UiChrome.text(c, Vector2(24.0, y), "RELEGATED", 10, UiChrome.C_DIM, bold)
		y += 16.0
		for row in summary["relegated"]:
			UiChrome.text(c, Vector2(32.0, y + 12.0), "%d" % int(row["position"]), 10, UiChrome.C_DIM, med)
			UiChrome.text(c, Vector2(54.0, y + 12.0), str(row["club"]), 11, UiChrome.C_DANGER, med)
			y += 16.0
		var scorers: Array = summary.get("top_scorers", [])
		if not scorers.is_empty():
			UiChrome.text_r(c, vp.x - 24.0, HEADER + 18.0, "TOP SCORER  %s (%d)" % [str(scorers[0]["name"]),
				int(scorers[0]["goals"])], 11, UiChrome.C_SOFT, bold)

func _club_row(view: Dictionary, club_id: String) -> Dictionary:
	for row in view.get("table", []):
		if str(row["club_id"]) == club_id:
			return row
	return {}

# gd-tools: no cover end
