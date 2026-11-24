class_name LeagueScreen
extends Control

## God-mode league surface: New/Setup, Load, Continue hub, table, calendar,
## reports and podium. Screen holds state; sheets paint; season owns the sim.
## Input arrives in design space from `LeagueHost`.

signal closed
signal match_requested(home: String, away: String, fixture_id: String)
signal season_opened(season: LeagueSeason)
## Club row: host opens that club's team page over the season.
signal club_requested(club_id: String)
## Goal ▶: host plays that stored clip over the broadcast.
signal goal_highlight_requested(fixture_id: String, goal_index: int)

const MODE_HUB := "hub"
const MODE_WIZARD := "wizard"
const MODE_LOAD := "load"
const MODE_TABLE := "table"
const MODE_CALENDAR := "calendar"
const MODE_REPORT := "report"
const MODE_PODIUM := "podium"

var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)
## Pointer button down: touch stand-in for hover (#99).
var holding := false

var mode := MODE_WIZARD
var season: LeagueSeason = null
var wizard := {"name": "League 1", "calendar_mode": "generated", "advance_mode": "fixture_days", "error": ""}
var saves: Array = []
var report: Dictionary = {}
var roundup: Array = []
var month := ""
var day := ""
var day_fixtures: Array = []
var days_cache := {}
## Every door on the sheet, with the rows moved by the body's scroll offset.
var buttons: Array:
	get:
		return body.button_rects() if body != null else []
var body: LeagueBody = null
var hub: LeagueSheet = LeagueSheet.new()
var book: LeagueBook = LeagueBook.new()
## Date strips: the chrome's own, and the active sheet's rows on screen (#99).
var hints := DateHints.new()
var rows_hints: DateHints = null
var tooltip: DateOverlay = null
var _last_mode := ""
## Pose -> [sheet, layout, body painter, chrome painter].
var _poses := {
	MODE_HUB: ["hub", "hub_layout", "draw_hub_body", "draw_hub_chrome"],
	MODE_WIZARD: ["hub", "wizard_layout", "draw_wizard_body", "draw_wizard_chrome"],
	MODE_LOAD: ["hub", "load_layout", "draw_load_body", "draw_load_chrome"],
	MODE_TABLE: ["book", "table_layout", "draw_table_body", "draw_table_chrome"],
	MODE_CALENDAR: ["book", "calendar_layout", "draw_calendar_body", "draw_calendar_chrome"],
	MODE_REPORT: ["book", "report_layout", "draw_report_body", "draw_report_chrome"],
	MODE_PODIUM: ["book", "podium_layout", "draw_podium_body", "draw_podium_chrome"],
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	month = str(Time.get_date_dict_from_system()["year"]) + "-" + "%02d" % int(Time.get_date_dict_from_system()["month"])
	body = LeagueBody.new()
	body.name = "Body"
	add_child(body)
	tooltip = DateOverlay.attach(self, body, false)
	resized.connect(refresh)

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp

func is_open() -> bool:
	return visible and mode != ""

# ------------------------------------------------------------------ open ---

func open_wizard() -> void:
	mode = MODE_WIZARD
	wizard = {"name": "League %d" % (saves.size() + 1), "calendar_mode": "generated",
		"advance_mode": "fixture_days", "error": ""}
	visible = true
	refresh()

func open_load() -> void:
	mode = MODE_LOAD
	saves = LeagueSave.list()
	visible = true
	refresh()

func open_season(target: LeagueSeason, show_podium: bool = false) -> void:
	season = target
	season_opened.emit(target)
	if show_podium or (target != null and str(target.state().get("status", "")) == "complete"):
		mode = MODE_PODIUM
	else:
		mode = MODE_HUB
	month = LeagueBook.state_month(season, month)
	visible = true
	refresh()

func show_report(fixture_id: String) -> void:
	if season == null:
		return
	report = season.report(fixture_id)
	roundup = []
	mode = MODE_REPORT
	refresh()

func show_roundup(reports: Array) -> void:
	report = {}
	roundup = reports
	mode = MODE_REPORT
	refresh()

func close() -> void:
	visible = false
	mode = MODE_HUB
	closed.emit()

# --------------------------------------------------------------- state ----

func current_view() -> Dictionary:
	if mode == MODE_WIZARD or mode == MODE_LOAD:
		return wizard if mode == MODE_WIZARD else {"saves": saves}
	var rules: Dictionary = season.rules if season != null else LeagueRules.defaults()
	var state: Dictionary = season.state() if season != null else {"rules": rules}
	if mode == MODE_TABLE:
		return {"table": state.get("table", []), "rules": state.get("rules", rules),
			"name": state.get("name", ""), "date": state.get("date", "")}
	if mode == MODE_CALENDAR:
		return {"month": month, "day": day, "days": days_cache, "day_fixtures": day_fixtures}
	if mode == MODE_REPORT:
		if not roundup.is_empty():
			return {"roundup": roundup, "day": str(roundup[0]["fixture"]["kickoff"]) if roundup[0].has("fixture") else ""}
		return {
			"fixture": report.get("fixture", {}), "events": report.get("events", []),
			"highlights": report.get("highlights", []),
			"day": str((report.get("fixture", {}) as Dictionary).get("kickoff", "")),
		}
	if mode == MODE_PODIUM:
		return {"summary": state.get("summary", {}), "name": state.get("name", ""),
			"table": state.get("table", []), "rules": state.get("rules", rules)}
	var view: Dictionary = state.duplicate()
	if season != null:
		view["plan"] = season.plan()
		view["can_suggest"] = bool(view.get("can_suggest", false))
		view["settling"] = season.finishing
	else:
		view["plan"] = []
	view["screen"] = mode
	return view

# ---------------------------------------------------------------- layout ---

func refresh() -> void:
	var vp := design_vp()
	var view := current_view()
	var pose: Array = _poses.get(mode, [])
	if body == null or pose.is_empty():
		return
	var sheet: RefCounted = hub if str(pose[0]) == "hub" else book
	rows_hints = hub.hints if str(pose[0]) == "hub" else book.hints
	var items: Array = Callable(sheet, str(pose[1])).call(vp, view)
	var content := body.set_sheet(items, vp, mode != _last_mode)
	body.painter = Callable(sheet, str(pose[2])).bind(vp, UiChrome.fonts(), content, view)
	_last_mode = mode
	queue_redraw()

## Hit test walks back to front so later items (e.g. a delete chip) win.
func button_at(p: Vector2) -> String:
	return body.hit(p) if body != null else ""

## Wheel, trackpad, drag and keys; wide tables also pan sideways.
func scroll_by(delta: float, dx: float = 0.0) -> void:
	if body != null:
		body.pan_by(Vector2(dx, delta))

func click(id: String) -> void:
	if id == "":
		return
	if id.begins_with("match:"):
		show_report(id.substr(6))
	elif id.begins_with("goal:"):
		play_goal(int(id.substr(5)))
	elif id.begins_with("club:"):
		club_requested.emit(id.substr(5))
	elif id == "back":
		_back()
	elif id.begins_with("toggle:"):
		_toggle(id.substr(7))
	elif id.begins_with("fixture:"):
		_press_fixture(id.substr(8))
	elif id.begins_with("open:"):
		_open_save(id.substr(5))
	elif id.begins_with("delete:"):
		var slug := id.substr(7)
		if season != null and season.save.slug == slug:
			season.close()
			season = null
		LeagueSave.remove(slug)
		saves = LeagueSave.list()
		refresh()
	elif id.begins_with("mode:"):
		wizard["calendar_mode"] = id.substr(5)
		refresh()
	elif id.begins_with("adv:"):
		wizard["advance_mode"] = id.substr(4)
		refresh()
	elif id.begins_with("day:"):
		LeagueCalendar.pick(self, id.substr(4))
	elif id.begins_with("month:"):
		LeagueCalendar.shift(self, int(id.substr(6)))
	elif id == "continue":
		_continue()
	elif id == "suggest":
		season.suggest()
		refresh()
	elif id == "table":
		mode = MODE_TABLE
		book.table.attach(season.save if season != null else null)
		refresh()
	elif id.begins_with("tbl:"):
		if season != null and book.table.press(id, season.save):
			refresh()
	elif id == "calendar":
		mode = MODE_CALENDAR
		LeagueCalendar.open(self)
	elif id == "podium":
		mode = MODE_PODIUM
		refresh()
	elif id == "menu":
		close()
	elif id == "create":
		_create()
	elif id == "name":
		refresh()

func _back() -> void:
	if mode == MODE_HUB or mode == MODE_WIZARD or mode == MODE_LOAD or mode == MODE_PODIUM:
		close()
	else:
		mode = MODE_HUB
		refresh()

# --------------------------------------------------------------- highlights ---

## Play one goal of the report on screen. The host owns the viewer; the screen
## only names the fixture and the goal's ordinal.
func play_goal(index: int) -> void:
	if mode != MODE_REPORT or not has_clip(index):
		return
	goal_highlight_requested.emit(str((report.get("fixture", {}) as Dictionary).get("id", "")), index)

func has_clip(index: int) -> bool:
	for row in report.get("highlights", []):
		if int(row.get("goal_index", -1)) == index:
			return true
	return false

# --------------------------------------------------------------- actions ---

func _create() -> void:
	var created := LeagueSeason.create(str(wizard["name"]), str(wizard["calendar_mode"]),
		str(wizard["advance_mode"]), 0)
	if created == null:
		wizard["error"] = "The season could not be created."
		refresh()
		return
	season = created
	season_opened.emit(created)
	mode = MODE_HUB
	month = LeagueBook.state_month(season, month)
	refresh()

func _open_save(slug: String) -> void:
	var opened := LeagueSeason.open(slug)
	if opened == null:
		wizard["error"] = "That save could not be opened."
		mode = MODE_WIZARD
		refresh()
		return
	open_season(opened, str(opened.state().get("status", "")) == "complete")

func _continue() -> void:
	if season == null or season.finishing:
		refresh()
		return
	var result := season.advance()
	var played: Array = result.get("played", [])
	if str(result.get("status", "")) == "complete" or bool(result.get("complete", false)):
		mode = MODE_PODIUM
		month = LeagueBook.state_month(season, month)
		refresh()
		return
	# Pending watch: Continue opens it instead of settling the day (#100).
	var pending: Array = result.get("pending", [])
	if not pending.is_empty():
		var watch := season.start_watch(str(pending[0]["id"]))
		if not watch.is_empty():
			match_requested.emit(str(watch["home"]), str(watch["away"]), str(watch["fixture_id"]))
			return
	if not played.is_empty():
		show_roundup(played)
		return
	month = LeagueBook.state_month(season, month)
	refresh()

func _toggle(fixture_id: String) -> void:
	if season == null:
		return
	var fx := season.record.fixture(fixture_id)
	if fx.is_empty() or str(fx["status"]) == "played":
		return
	season.set_watch(fixture_id, int(fx["watched"]) != 1)
	refresh()

func _press_fixture(fixture_id: String) -> void:
	if season == null:
		return
	var fx := season.record.fixture(fixture_id)
	if fx.is_empty():
		return
	if str(fx["status"]) == "played":
		show_report(fixture_id)
	elif int(fx["watched"]) == 1:
		var watch := season.start_watch(fixture_id)
		if not watch.is_empty():
			match_requested.emit(str(watch["home"]), str(watch["away"]), str(watch["fixture_id"]))
	else:
		_toggle(fixture_id)

# ---------------------------------------------------------------- input ----

func key(code: int) -> bool:
	if mode == MODE_WIZARD and _type_name(code):
		return true
	if mode == MODE_REPORT and code >= KEY_1 and code <= KEY_9:
		var want := code - KEY_1
		if has_clip(want):
			play_goal(want)
			return true
	if code == KEY_ESCAPE or code == KEY_BACKSPACE:
		_back()
		return true
	if mode == MODE_HUB and (code == KEY_ENTER or code == KEY_KP_ENTER):
		_continue()
		return true
	if code == KEY_UP or code == KEY_W:
		scroll_by(-120.0)
	elif code == KEY_DOWN or code == KEY_S:
		scroll_by(120.0)
	elif code == KEY_PAGEUP:
		scroll_by(-body.size.y * 0.9)
	elif code == KEY_PAGEDOWN:
		scroll_by(body.size.y * 0.9)
	elif code == KEY_HOME:
		scroll_by(-1.0e7)
	elif code == KEY_END:
		scroll_by(1.0e7)
	else:
		return false
	return true

func _type_name(code: int) -> bool:
	var typed: Array = LeagueSheet.type_name(str(wizard["name"]), code)
	if bool(typed[0]):
		wizard["name"] = str(typed[1])
		refresh()
	return bool(typed[0])

# ----------------------------------------------------------------- paint ---

func _draw() -> void:
	var vp := design_vp()
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.008, 0.014, 0.018, 0.94))
	var pose: Array = _poses.get(mode, [])
	if pose.is_empty():
		return
	var sheet: RefCounted = hub if str(pose[0]) == "hub" else book
	var fonts := UiChrome.fonts()
	hints.clear()
	Callable(sheet, str(pose[3])).call(self, vp, fonts, current_view(), hints)
	if body != null:
		for item in body.pinned:
			var rect: Rect2 = item["rect"]
			if str(item["kind"]) == "button":
				hub.draw_button(self, rect, str(item["label"]), fonts["bold"], bool(item.get("primary", false)))
			elif str(item["kind"]) == "chip":
				hub.draw_chip(self, rect, str(item["label"]), fonts["bold"])
