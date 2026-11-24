class_name LeagueScreen
extends Control

## God-mode league surface: New/Setup, Load, Continue hub, table, calendar,
## reports and podium. The screen holds state and paint; the sheets draw a pose;
## `LeagueDoors` owns the keys, presses and season actions; the season owns the
## sim. Input arrives in design space from `LeagueHost`.

signal closed
signal match_requested(home: String, away: String, fixture_id: String)
signal season_opened(season: LeagueSeason)
## Club row: host opens that club's team page over the season.
signal club_requested(club_id: String)
## Goal ▶: host plays that stored clip over the broadcast.
signal goal_highlight_requested(fixture_id: String, goal_index: int)
## The System sheet asked the shell to close the game.
signal quit_requested

const MODE_HUB := "hub"
const MODE_WIZARD := "wizard"
const MODE_LOAD := "load"
const MODE_TABLE := "table"
const MODE_CALENDAR := "calendar"
const MODE_REPORT := "report"
const MODE_PODIUM := "podium"
## The season's own save/exit dialog (#109).
const MODE_SYSTEM := "system"

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
## The season's own save/exit dialog (#109), its own pose beside hub and book.
var system := LeagueSystemSheet.new()
## What the System sheet is showing: the last acknowledgement, a refusal, and
## the Save As name field while it is open.
var sys := {"status": "", "error": "", "naming": false, "name": ""}
## Where the load list was opened from, so BACK returns there (menu or season).
var load_from := "menu"
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
	MODE_SYSTEM: ["system", "layout", "draw_body", "draw_chrome"],
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
	load_from = "menu"
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

## Open a saved season, replacing the one on screen. The doors own the swap.
func open_save(slug: String) -> void:
	LeagueDoors.open_save(self, slug)

# --------------------------------------------------------------- state ----

func current_view() -> Dictionary:
	return LeagueView.build(self)

# ---------------------------------------------------------------- layout ---

func refresh() -> void:
	var vp := design_vp()
	var view := current_view()
	var pose: Array = _poses.get(mode, [])
	if body == null or pose.is_empty():
		return
	var sheet := _sheet(pose)
	rows_hints = sheet.hints
	var items: Array = Callable(sheet, str(pose[1])).call(vp, view)
	var content := body.set_sheet(items, vp, mode != _last_mode)
	body.painter = Callable(sheet, str(pose[2])).bind(vp, UiChrome.fonts(), content, view)
	_last_mode = mode
	queue_redraw()

## The sheet that owns a pose: the hub sheets, the reading book, or the System
## dialog (which is its own module).
func _sheet(pose: Array) -> RefCounted:
	match str(pose[0]):
		"book":
			return book
		"system":
			return system
	return hub

## Hit test walks back to front so later items (e.g. a delete chip) win.
func button_at(p: Vector2) -> String:
	return body.hit(p) if body != null else ""

## Wheel, trackpad, drag and keys; wide tables also pan sideways.
func scroll_by(delta: float, dx: float = 0.0) -> void:
	if body != null:
		body.pan_by(Vector2(dx, delta))

# --------------------------------------------------------------- highlights ---

## True when the report on screen carries a stored clip for a goal ordinal.
func has_clip(index: int) -> bool:
	return LeagueDoors.has_clip(self, index)

# ---------------------------------------------------------------- input ----

func click(id: String) -> void:
	LeagueDoors.press(self, id)

func key(code: int) -> bool:
	return LeagueDoors.key(self, code)

# ----------------------------------------------------------------- paint ---

func _draw() -> void:
	var vp := design_vp()
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0.008, 0.014, 0.018, 0.94))
	var pose: Array = _poses.get(mode, [])
	if pose.is_empty():
		return
	var sheet := _sheet(pose)
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
