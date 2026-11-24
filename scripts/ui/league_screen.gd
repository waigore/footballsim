class_name LeagueScreen
extends Control

## God-mode league surface: New/Setup, Load, Continue hub with its left panel,
## table, calendar, reports, Stats, Teams of Interest, System and podium. Screen
## holds state; sheets paint; season owns the sim. Input arrives in design space
## from `LeagueHost`; presses and keys are routed by `LeagueActions`.

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
## The panel's own readings (#103): matchday reports + podium, and the shortlist.
const MODE_STATS := "stats"
const MODE_INTEREST := "interest"

## Panel destination (LeaguePanel.pose) for each pose on screen.
const POSE_NAMES := {
	MODE_HUB: "fixtures", MODE_TABLE: "table", MODE_CALENDAR: "calendar",
	MODE_INTEREST: "interest", MODE_STATS: "stats", MODE_SYSTEM: "system",
	MODE_REPORT: "fixtures", MODE_PODIUM: "stats",
}

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
## Stats and Teams of Interest, the panel's two new readings (#103).
var sheet_extra := LeagueExtra.new()
## What the System sheet is showing: the last acknowledgement, a refusal, and
## the Save As name field while it is open.
var sys := {"status": "", "error": "", "naming": false, "name": ""}
## Where the load list was opened from, so BACK returns there (menu or season).
var load_from := "menu"
## Long-press interest menu, the left slide panel and the layer that paints them.
var menu := InterestMenu.new()
var panel := LeaguePanel.new()
var overlay: LeagueOverlay = null
var actions: LeagueActions = null
## The shortlist search field, and where BACK from a report returns (#103).
var interest_query := ""
var report_back := MODE_HUB
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
	MODE_STATS: ["extra", "stats_layout", "draw_stats_body", "draw_stats_chrome"],
	MODE_INTEREST: ["extra", "interest_layout", "draw_interest_body", "draw_interest_chrome"],
}

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	month = str(Time.get_date_dict_from_system()["year"]) + "-" + "%02d" % int(Time.get_date_dict_from_system()["month"])
	body = LeagueBody.new()
	body.name = "Body"
	add_child(body)
	tooltip = DateOverlay.attach(self, body, false)
	overlay = LeagueOverlay.new()
	overlay.name = "Overlay"
	overlay.ui_scale = ui_scale
	overlay.panel = panel
	overlay.menu = menu
	overlay.fonts = UiChrome.fonts()
	add_child(overlay)
	actions = LeagueActions.new(self)
	resized.connect(refresh)

## The slide animates on its own clock; a settled panel costs nothing and never
## blocks input.
func _process(delta: float) -> void:
	if visible and panel.update(delta):
		overlay.queue_redraw()

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
	interest_query = ""
	menu.hide()
	panel.close()
	panel.settle()
	visible = true
	refresh()

func open_load() -> void:
	mode = MODE_LOAD
	load_from = "menu"
	saves = LeagueSave.list()
	menu.hide()
	panel.close()
	panel.settle()
	visible = true
	refresh()

func open_season(target: LeagueSeason, show_podium: bool = false) -> void:
	season = target
	season_opened.emit(target)
	if show_podium or (target != null and str(target.state().get("status", "")) == "complete"):
		mode = MODE_PODIUM
	else:
		mode = MODE_HUB
	interest_query = ""
	report_back = MODE_HUB
	menu.hide()
	panel.close()
	panel.settle()
	month = LeagueBook.state_month(season, month)
	visible = true
	refresh()

func show_report(fixture_id: String) -> void:
	if season == null:
		return
	report = season.report(fixture_id)
	roundup = []
	mode = MODE_REPORT
	report_back = MODE_STATS if report_back == MODE_STATS else MODE_HUB
	refresh()

func show_roundup(reports: Array) -> void:
	report = {}
	roundup = reports
	mode = MODE_REPORT
	report_back = MODE_HUB
	refresh()

func close() -> void:
	visible = false
	mode = MODE_HUB
	menu.hide()
	panel.close()
	panel.settle()
	closed.emit()

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
	var content := body.set_sheet(items, vp, mode != _last_mode, _bottom_bar())
	body.painter = Callable(sheet, str(pose[2])).bind(vp, UiChrome.fonts(), content, view)
	panel.active = str(POSE_NAMES.get(mode, ""))
	overlay.active_pose = panel.active
	overlay.ui_scale = ui_scale
	_last_mode = mode
	overlay.queue_redraw()
	queue_redraw()

## Bottom chrome the pose reserves: the table keeps its chips.
func _bottom_bar() -> float:
	return LeagueSheet.BAR_H if mode == MODE_TABLE else 0.0

## The sheet that owns a pose: the hub sheets, the reading book, the System
## dialog (its own module) or the panel's two extra readings.
func _sheet(pose: Array) -> RefCounted:
	match str(pose[0]):
		"book":
			return book
		"system":
			return system
		"extra":
			return sheet_extra
	return hub

## Hit test walks back to front so later items (e.g. a delete chip) win. The
## panel and the interest menu sit above the body and take the press first.
func button_at(p: Vector2) -> String:
	var over_panel: String = panel.hit(p, design_vp())
	if over_panel != "":
		return over_panel
	if menu.open:
		var hit: String = menu.hit(p, design_vp())
		if hit != "":
			return hit
	return body.hit(p) if body != null else ""

## Wheel, trackpad, drag and keys; wide tables also pan sideways.
func scroll_by(delta: float, dx: float = 0.0) -> void:
	if body != null:
		body.pan_by(Vector2(dx, delta))

func click(id: String) -> void:
	actions.click(id)

func key(code: int) -> bool:
	return actions.key(code)

func open_save_now(slug: String) -> void:
	# Load replaces the season outright: the old save, its ledger and every cached
	# sheet reading go before the new file is bound, so nothing leaks across.
	LeagueSystemActions.unload(self)
	var opened := LeagueSeason.open(slug)
	if opened == null:
		wizard["error"] = "That save could not be opened."
		mode = MODE_WIZARD
		refresh()
		return
	open_season(opened, str(opened.state().get("status", "")) == "complete")

## Drop every reading the unloaded season owned, so the next save never paints
## the previous one's table, report or month.
func reset_season() -> void:
	season = null
	report = {}
	roundup = []
	day = ""
	day_fixtures = []
	days_cache = {}
	interest_query = ""
	report_back = MODE_HUB
	book.table.attach(null)
	LeagueSystemActions.reset(self)
	menu.hide()
	panel.close()
	panel.settle()
	mode = MODE_WIZARD
	refresh()

# --------------------------------------------------------------- interest ---

## The club painted under a point, read from the rows the body hit-tests.
func team_at(p: Vector2) -> String:
	if body == null or panel.is_open() or menu.open:
		return ""
	for item in body.button_rects():
		var rect: Rect2 = item["rect"]
		if not rect.has_point(p):
			continue
		if item.has("club_id"):
			return str(item["club_id"])
		if item.has("club"):
			return str((item["club"] as Dictionary).get("id", ""))
		var row: Dictionary = item.get("row", {})
		if row.has("club_id"):
			return str(row["club_id"])
		var fx: Dictionary = item.get("fixture", {})
		if fx.is_empty() and item.has("report"):
			fx = (item["report"] as Dictionary).get("fixture", {})
		if fx.is_empty():
			continue
		var kind := str(item.get("kind", ""))
		var pivot: float = rect.position.x + (100.0 if kind == "fixture" else 118.0)
		if kind == "result":
			pivot = rect.get_center().x
		return str(fx["home_club_id"]) if p.x < pivot else str(fx["away_club_id"])
	return ""

## A long-press landed here: raise the interest menu for the club under it.
func open_interest_at(p: Vector2) -> void:
	var club := team_at(p)
	if club == "" or season == null:
		return
	menu.show_at(club, str(PLRepository.shared().club(club).get("name", club)), p)
	overlay.queue_redraw()

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
