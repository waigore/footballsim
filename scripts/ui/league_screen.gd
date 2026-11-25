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
## The panel's two readings (#103): matchday reports + podium, and the shortlist.
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
var hub := LeagueHubSheet.new()
## New season and load list: each pose is its own sheet, so the hub never
## carries another screen's geometry.
var wizard_sheet := LeagueWizardSheet.new()
var load_sheet := LeagueLoadSheet.new()
## Style cache for the pinned doors, which are painted by the screen after the
## active sheet's own body.
var chrome_cache := {}
var book: LeagueBook = LeagueBook.new()
## The season's own save/exit dialog (#109), its own pose beside hub and book.
var system := LeagueSystemSheet.new()
## Stats and Teams of Interest, the panel's two new readings (#103).
var sheet_extra := LeagueExtra.new()
## The shortlist search field, and where BACK from a report returns (#103).
var interest_query := ""
var report_back := MODE_HUB
## The season's page history (#169): session state only, never saved. BACK walks
## it; MAIN MENU closes the season and empties it.
var nav := LeagueNavStack.new()
## The left slide panel and the layer that paints it above the body.
var panel := LeaguePanel.new()
var overlay: LeagueOverlay = null
## What the System sheet is showing: the last acknowledgement, a refusal, and
## the Save As name field while it is open.
var sys := {"status": "", "error": "", "naming": false, "name": ""}
## Where the load list was opened from, so BACK returns there (menu or season).
var load_from := "menu"
## Date strips: the chrome's own, and the active sheet's rows on screen (#99).
var hints := DateHints.new()
var rows_hints: DateHints = null
## Club names the sheet on screen painted (#107): the long press reads them to
## know which club is under the finger.
var rows_names: InterestNames = null
## The long press itself: the clock, the menu and the one write it makes.
var interest := InterestHold.new()
## The layer that paints the menu above the body and the panel.
var menu_layer: InterestLayer = null
var tooltip: DateOverlay = null
var _last_mode := ""
## Pose -> [sheet, layout, body painter, chrome painter].
var _poses := {
	MODE_HUB: ["hub", "hub_layout", "draw_hub_body", "draw_hub_chrome"],
	MODE_WIZARD: ["wizard", "wizard_layout", "draw_wizard_body", "draw_wizard_chrome"],
	MODE_LOAD: ["load", "load_layout", "draw_load_body", "draw_load_chrome"],
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
	overlay.panel = panel
	overlay.fonts = UiChrome.fonts()
	add_child(overlay)
	resized.connect(refresh)
	# Where a club is printed, which season owns the shortlist, and how to paint
	# the sheet again once it moved (#107).
	interest.club_at = func(p: Vector2) -> String:
		if rows_names == null or body == null:
			return ""
		if not Rect2(body.position, body.size).has_point(p):
			return ""
		return rows_names.at(p + Vector2(body.hscroll, body.scroll))
	interest.season_of = func(): return season
	interest.on_changed = refresh
	menu_layer = InterestLayer.new()
	menu_layer.hold = interest
	menu_layer.screen = self
	add_child(menu_layer)

## The slide animates on its own clock; a settled panel costs nothing and never
## blocks input.
func _process(delta: float) -> void:
	if interest.tick(delta):
		overlay.queue_redraw()
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
	nav.clear()
	wizard = {"name": "League %d" % (saves.size() + 1), "calendar_mode": "generated",
		"advance_mode": "fixture_days", "error": ""}
	visible = true
	refresh()

func open_load() -> void:
	mode = MODE_LOAD
	nav.clear()
	load_from = "menu"
	saves = LeagueSave.list()
	visible = true
	refresh()

func open_season(target: LeagueSeason, show_podium: bool = false) -> void:
	season = target
	# A season opens at its own root: no history can point into a save that is
	# not the one on screen.
	nav.clear()
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
	push_page()
	report = season.report(fixture_id)
	roundup = []
	mode = MODE_REPORT
	refresh()

func show_roundup(reports: Array) -> void:
	push_page()
	report = {}
	roundup = reports
	mode = MODE_REPORT
	refresh()

## Remember the page on screen so BACK can return to it. The one place that
## pushes, so every door down into a sheet leaves the same trail (#169).
func push_page() -> void:
	nav.push(LeagueNavStack.snapshot(self))

func close() -> void:
	visible = false
	mode = MODE_HUB
	# Leaving the league ends its history: a reopened season starts at its root.
	nav.clear()
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
	rows_names = sheet.get("names") if sheet.get("names") is InterestNames else null
	interest.vp = vp
	if mode != _last_mode:
		interest.close()
	var items: Array = Callable(sheet, str(pose[1])).call(vp, view)
	# BACK is visible at the root of the season's history, but not actionable:
	# nothing behind it, and the main menu is not a page of the league (#169).
	var can_back := LeagueDoors.can_back(self)
	for item in items:
		if str(item.get("id", "")) == "back":
			item["disabled"] = not can_back
	var content := body.set_sheet(items, vp, mode != _last_mode, _bottom_bar())
	body.painter = Callable(sheet, str(pose[2])).bind(vp, UiChrome.fonts(), content, view)
	panel.active = str(POSE_NAMES.get(mode, ""))
	overlay.active_pose = panel.active
	overlay.ui_scale = ui_scale
	_last_mode = mode
	overlay.queue_redraw()
	queue_redraw()

## Bottom chrome the pose reserves: only the table keeps its chips.
func _bottom_bar() -> float:
	return LeagueSheet.BAR_H if mode == MODE_TABLE else 0.0

## The sheet that owns a pose: the hub sheets, the reading book, or the System
## dialog (which is its own module).
func _sheet(pose: Array) -> RefCounted:
	match str(pose[0]):
		"wizard":
			return wizard_sheet
		"load":
			return load_sheet
		"book":
			return book
		"system":
			return system
		"extra":
			return sheet_extra
	return hub

## Hit test walks back to front so later items (e.g. a delete chip) win. The
## open menu is in front of everything and answers every press itself (#107).
func button_at(p: Vector2) -> String:
	if interest.is_open():
		return interest.menu.hit(p, design_vp())
	var over_panel: String = panel.hit(p, design_vp())
	if over_panel != "":
		return over_panel
	return body.hit(p) if body != null else ""

## Wheel, trackpad, drag and keys; wide tables also pan sideways. The sheet is
## frozen while the menu is up, so a press under it never scrolls the page.
func scroll_by(delta: float, dx: float = 0.0) -> void:
	if interest.is_open():
		return
	if body != null:
		body.pan_by(Vector2(dx, delta))

# --------------------------------------------------------------- highlights ---

## True when the report on screen carries a stored clip for a goal ordinal.
func has_clip(index: int) -> bool:
	return LeagueDoors.has_clip(self, index)

# ---------------------------------------------------------------- input ----

func click(id: String) -> void:
	if interest.click(id):
		return
	LeagueDoors.press(self, id)

func key(code: int) -> bool:
	# ESC puts the menu away first: it is the top-most surface while it is up.
	if interest.is_open() and (code == KEY_ESCAPE or code == KEY_BACKSPACE):
		interest.close()
		refresh()
		return true
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
		# Pinned doors keep the sheet's paint grammar (it owns the style cache).
		for item in body.pinned:
			var rect: Rect2 = item["rect"]
			if str(item["kind"]) == "button":
				LeagueSheet.draw_button(self, chrome_cache, rect, str(item["label"]), fonts["bold"],
					bool(item.get("primary", false)), bool(item.get("disabled", false)))
			elif str(item["kind"]) == "chip":
				LeagueSheet.draw_chip(self, chrome_cache, rect, str(item["label"]), fonts["bold"])
