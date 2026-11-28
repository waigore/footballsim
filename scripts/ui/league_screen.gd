class_name LeagueScreen
extends Control


signal closed
signal match_requested(home: String, away: String, fixture_id: String)
signal season_opened(season: LeagueSeason)

signal club_requested(club_id: String)

signal goal_highlight_requested(fixture_id: String, goal_index: int)

signal quit_requested

const MODE_HUB := "hub"
const MODE_WIZARD := "wizard"
const MODE_LOAD := "load"
const MODE_TABLE := "table"
const MODE_CALENDAR := "calendar"
const MODE_REPORT := "report"
const MODE_PODIUM := "podium"

const MODE_SYSTEM := "system"

const MODE_STATS := "stats"
const MODE_INTEREST := "interest"
const MODE_EUROPE := "europe"
const MODE_EUROPE_STAGE := "europe_stage"
const MODE_EUROPE_DRAW := "europe_draw"


var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)

var holding := false

var mode := MODE_WIZARD
var season: LeagueSeason = null
var wizard := {"name": "", "calendar_mode": "generated", "advance_mode": "fixture_days",
	"competitions": ["PL"], "uefa": true, "error": ""}
var saves: Array = []

var delete := LeagueDelete.new()
var report: Dictionary = {}
var roundup: Array = []
var report_filter := {"league": "", "interest": false}
var month := ""
var day := ""
var day_fixtures: Array = []
var days_cache := {}

var buttons: Array:
	get:
		return body.button_rects() if body != null else []
var body: LeagueBody = null


var pinned: LeaguePinned = null
var hub: LeagueSheet = LeagueSheet.new()

var start := LeagueStartSheet.new()
var book: LeagueBook = LeagueBook.new()

var system := LeagueSystemSheet.new()

var sheet_stats := LeagueStatsSheet.new()
var sheet_interest := LeagueInterestSheet.new()
var sheet_europe := LeagueEuropeSheet.new()
var sheet_europe_stage := LeagueEuropeStage.new()
var sheet_europe_draw := LeagueEuropeDraw.new()

var europe := {"comp": "", "tab": "", "round": ""}
var europe_draw := {"competition": "", "round": "", "revealed": 0, "done": false, "t": 0.0}

var calendar_filter := ""

var interest_query := ""


var stats_filter := {"league": "", "month": "", "team": "", "stat": "goals"}
var report_back := MODE_HUB


var nav := LeagueNavStack.new()

var panel := LeaguePanel.new()
var overlay: LeagueOverlay = null


var sys := {"status": "", "error": "", "naming": false, "name": ""}

var load_from := "menu"

var hints := DateHints.new()
var rows_hints: DateHints = null


var rows_names: InterestNames = null

var interest := InterestHold.new()


var focus := LeagueFieldFocus.new()

var menu_layer: InterestLayer = null
var tooltip: DateOverlay = null
var pages: LeagueScreenPages = null
var input: LeagueScreenInput = null
var _last_mode := ""

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	month = str(Time.get_date_dict_from_system()["year"]) + "-" + "%02d" % int(Time.get_date_dict_from_system()["month"])
	body = LeagueBody.new()
	body.name = "Body"
	add_child(body)


	pinned = LeaguePinned.new()
	pinned.name = "Pinned"
	pinned.body = body
	add_child(pinned)
	tooltip = DateOverlay.attach(self, body, false)
	overlay = LeagueOverlay.new()
	overlay.name = "Overlay"
	overlay.panel = panel
	overlay.fonts = UiChrome.fonts()
	overlay.screen = self
	overlay.delete = delete
	add_child(overlay)
	resized.connect(refresh)


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
	pages = LeagueScreenPages.new(self)
	input = LeagueScreenInput.new(self)


func _process(delta: float) -> void:
	if interest.tick(delta):
		overlay.queue_redraw()
	if visible and panel.update(delta):
		overlay.queue_redraw()
	if visible and LeagueEuropeActions.tick(self, delta):
		overlay.queue_redraw()

func design_vp() -> Vector2:
	var vp: Vector2 = size / maxf(ui_scale, 0.001)
	if vp.x <= 0.0 or vp.y <= 0.0:
		vp = get_viewport().get_visible_rect().size / maxf(ui_scale, 0.001)
	return vp

func is_open() -> bool:
	return visible and mode != ""


func open_wizard() -> void:
	if pages != null:
		pages.open_wizard()

func open_load() -> void:
	if pages != null:
		pages.open_load()

func open_season(target: LeagueSeason, show_podium: bool = false) -> void:
	if pages != null:
		pages.open_season(target, show_podium)

func show_report(fixture_id: String) -> void:
	if pages != null:
		pages.show_report(fixture_id)

func show_roundup(reports: Array) -> void:
	if pages != null:
		pages.show_roundup(reports)


func push_page() -> void:
	if pages != null:
		pages.push_page()

func close() -> void:
	if pages != null:
		pages.close()


func open_save(slug: String) -> void:
	if pages != null:
		pages.open_save(slug)


func current_view() -> Dictionary:
	return LeagueView.build(self)


func refresh() -> void:
	if pages != null:
		pages.refresh()


func delete_confirm_open() -> bool:
	return input.delete_confirm_open() if input != null else false


func button_at(p: Vector2) -> String:
	return input.button_at(p) if input != null else ""


func scroll_by(delta: float, dx: float = 0.0) -> void:
	if input != null:
		input.scroll_by(delta, dx)


func has_clip(index: int) -> bool:
	return input.has_clip(index) if input != null else false


func click(id: String) -> void:
	if input != null:
		input.click(id)

func key(code: int) -> bool:
	return input.key(code) if input != null else false


func text_key(code: int, unicode: int) -> bool:
	return input.text_key(code, unicode) if input != null else false


func _draw() -> void:
	if pages != null:
		pages.paint(design_vp())
