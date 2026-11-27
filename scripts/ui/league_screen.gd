class_name LeagueScreen
extends Control

## God-mode league surface: New/Setup, Load, Continue hub, table, calendar,
## reports and podium. The screen holds state and paint; the sheets draw a pose;
## `LeagueDoors` owns the keys and presses, `LeagueSeasonDoors` the season's own
## actions and `LeagueGoalDoors` the report's goal doors; the season owns the
## sim. Input arrives in design space from `LeagueHost`.
##
## Open/close and pose routing live in `LeagueScreenPages`; hit-testing, scroll
## and keys in `LeagueScreenInput`, so this Control stays inside its P3 size
## and method budget.

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


var ui_scale := 1.0
var touch := false
var mouse := Vector2(-1000, -1000)
## Pointer button down: touch stand-in for hover (#99).
var holding := false

var mode := MODE_WIZARD
var season: LeagueSeason = null
var wizard := {"name": LeagueStartSheet.SAVE_NAME, "calendar_mode": "generated", "advance_mode": "fixture_days",
	"competitions": ["PL"], "error": ""}
var saves: Array = []
## The load list's delete question, over the sheet that raised it (DR-20261125-06).
var delete := LeagueDelete.new()
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
## The doors each sheet pins in screen space: BACK, CONTINUE, the table's
## readings. It is a sibling above the body, because the body clips its own
## paint away outside the scrolling band (#284).
var pinned: LeaguePinned = null
var hub: LeagueSheet = LeagueSheet.new()
## The menu-level front door: New League and Load are their own pose sheet.
var start := LeagueStartSheet.new()
var book: LeagueBook = LeagueBook.new()
## The season's own save/exit dialog (#109), its own pose beside hub and book.
var system := LeagueSystemSheet.new()
## Stats and Teams of Interest, the panel's two new readings (#103).
var sheet_extra := LeagueExtra.new()
## The shortlist search field, and where BACK from a report returns (#103).
var interest_query := ""
## STATS filters (#189): league, month, team query and the leader stat. Session
## state, so a filtered reading never rewrites the save.
var stats_filter := {"league": "", "month": "", "team": "", "stat": "goals"}
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
## Which painted text field owns the on-screen keyboard (#201). A touch sheet
## has no `LineEdit` to hand the platform, so the sheet raises the keyboard for
## the field the player pressed and puts it away when the field leaves.
var focus := LeagueFieldFocus.new()
## The layer that paints the menu above the body and the panel.
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
	# The pinned doors are laid out in screen space, outside the band the body
	# clips itself to, so they get their own unclipped layer above it (#284).
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
	pages = LeagueScreenPages.new(self)
	input = LeagueScreenInput.new(self)

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

## Remember the page on screen so BACK can return to it. The one place that
## pushes, so every door down into a sheet leaves the same trail (#169).
func push_page() -> void:
	if pages != null:
		pages.push_page()

func close() -> void:
	if pages != null:
		pages.close()

## Open a saved season, replacing the one on screen. The doors own the swap.
func open_save(slug: String) -> void:
	if pages != null:
		pages.open_save(slug)

# --------------------------------------------------------------- state ----

func current_view() -> Dictionary:
	return LeagueView.build(self)

# ---------------------------------------------------------------- layout ---

func refresh() -> void:
	if pages != null:
		pages.refresh()

## True while the load list is waiting for a delete confirmation. Everything
## behind the dialog is frozen until it is answered.
func delete_confirm_open() -> bool:
	return input.delete_confirm_open() if input != null else false

## Hit test walks back to front so later items (e.g. a delete chip) win.
func button_at(p: Vector2) -> String:
	return input.button_at(p) if input != null else ""

## Wheel, trackpad, drag and keys; wide tables also pan sideways.
func scroll_by(delta: float, dx: float = 0.0) -> void:
	if input != null:
		input.scroll_by(delta, dx)

# --------------------------------------------------------------- highlights ---

## True when the report on screen carries a stored clip for a goal ordinal.
func has_clip(index: int) -> bool:
	return input.has_clip(index) if input != null else false

# ---------------------------------------------------------------- input ----

func click(id: String) -> void:
	if input != null:
		input.click(id)

func key(code: int) -> bool:
	return input.key(code) if input != null else false

## One character the platform typed (#201). Soft keyboard text arrives here.
func text_key(code: int, unicode: int) -> bool:
	return input.text_key(code, unicode) if input != null else false

# ----------------------------------------------------------------- paint ---

func _draw() -> void:
	if pages != null:
		pages.paint(design_vp())
