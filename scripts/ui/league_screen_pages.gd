class_name LeagueScreenPages
extends RefCounted

## League sheet open/close and pose routing. The Control keeps the state and
## paint; this module owns which page is on screen so `LeagueScreen` stays
## inside its P3 size and method budget.

var screen = null

func _init(host: Control) -> void:
	screen = host

# ------------------------------------------------------------------ open ---

func open_wizard() -> void:
	screen.mode = LeagueScreen.MODE_WIZARD
	screen.delete.clear()
	screen.nav.clear()
	screen.wizard = {"name": LeagueStartSheet.SAVE_NAME,
		"calendar_mode": "generated", "advance_mode": "fixture_days",
		"competitions": ["PL"], "error": ""}
	screen.visible = true
	screen.refresh()

func open_load() -> void:
	screen.mode = LeagueScreen.MODE_LOAD
	screen.delete.clear()
	screen.nav.clear()
	screen.load_from = "menu"
	screen.saves = LeagueSaveCatalog.list()
	screen.visible = true
	screen.refresh()

func open_season(target: LeagueSeason, show_podium: bool = false) -> void:
	screen.season = target
	screen.delete.clear()
	# A season opens at its own root: no history can point into a save that is
	# not the one on screen.
	screen.nav.clear()
	screen.season_opened.emit(target)
	if show_podium or (target != null and str(target.state().get("status", "")) == "complete"):
		screen.mode = LeagueScreen.MODE_PODIUM
	else:
		screen.mode = LeagueScreen.MODE_HUB
	screen.month = LeagueMonth.state_month(screen.season, screen.month)
	screen.visible = true
	screen.refresh()

func show_report(fixture_id: String) -> void:
	if screen.season == null:
		return
	push_page()
	screen.report = screen.season.report(fixture_id)
	screen.roundup = []
	screen.mode = LeagueScreen.MODE_REPORT
	screen.refresh()

func show_roundup(reports: Array) -> void:
	push_page()
	screen.report = {}
	screen.roundup = reports
	screen.mode = LeagueScreen.MODE_REPORT
	screen.refresh()

## Remember the page on screen so BACK can return to it. The one place that
## pushes, so every door down into a sheet leaves the same trail (#169).
func push_page() -> void:
	screen.nav.push(LeagueNavStack.snapshot(screen))

func close() -> void:
	screen.visible = false
	screen.mode = LeagueScreen.MODE_HUB
	screen.delete.clear()
	# A keyboard is part of being on a field: leaving the sheet puts it away.
	screen.focus.blur()
	# Leaving the league ends its history: a reopened season starts at its root.
	screen.nav.clear()
	screen.closed.emit()

## Open a saved season, replacing the one on screen. The doors own the swap.
func open_save(slug: String) -> void:
	LeagueDoors.open_save(screen, slug)

# ---------------------------------------------------------------- layout ---

## Bottom chrome the pose reserves: only the table keeps its chips.
func bottom_bar() -> float:
	return LeagueChrome.BAR_H if screen.mode == LeagueScreen.MODE_TABLE else 0.0

## The sheet that owns a pose: the hub sheets, the reading book, or the System
## dialog (which is its own module).
func sheet(pose: Array) -> RefCounted:
	match str(pose[0]):
		"start":
			return screen.start
		"book":
			return screen.book
		"system":
			return screen.system
		"extra":
			return screen.sheet_extra
	return screen.hub

## Rebuild the body, pinned doors and panel from the mode on screen.
func refresh() -> void:
	var vp: Vector2 = screen.design_vp()
	var view: Dictionary = LeagueView.build(screen)
	# A confirmation belongs to the load list: any other pose puts it away.
	if screen.mode != LeagueScreen.MODE_LOAD:
		screen.delete.clear()
	var pose: Array = LeagueView.pose(screen.mode)
	if screen.body == null or pose.is_empty():
		return
	var owned: RefCounted = sheet(pose)
	screen.rows_hints = owned.hints
	screen.rows_names = owned.get("names") if owned.get("names") is InterestNames else null
	screen.interest.vp = vp
	if screen.mode != screen._last_mode:
		screen.interest.close()
	var items: Array = Callable(owned, str(pose[1])).call(vp, view)
	# BACK is visible at the root of the season's history, but not actionable:
	# nothing behind it, and the main menu is not a page of the league (#169).
	var can_back: bool = LeagueDoors.can_back(screen)
	for item in items:
		if str(item.get("id", "")) == "back":
			item["disabled"] = not can_back
	var content: Array = screen.body.set_sheet(items, vp, screen.mode != screen._last_mode, bottom_bar())
	var fonts: Dictionary = UiChrome.fonts()
	screen.body.painter = Callable(owned, str(pose[2])).bind(vp, fonts, content, view)
	# The pinned layer paints the doors the sheet pins outside the body's band,
	# with the sheet's paint grammar and the hub's style cache. The body keeps
	# its own pause: a frozen body answers no row and no pinned door.
	screen.pinned.fonts = fonts
	screen.pinned.cache = screen.hub.cache
	screen.pinned.size = vp
	screen.pinned.queue_redraw()
	screen.body.frozen = screen.delete_confirm_open()
	screen.panel.active = LeagueView.panel_reading(screen.mode)
	# A form that exists before a season does has no readings behind it, so the
	# drawer is put away rather than left out over the form (#273).
	if screen.panel.active == "":
		screen.panel.close()
		screen.panel.settle()
	# The drawer door is the season's only way to its other readings, so it is
	# sized for the pointer that will press it (#204).
	screen.panel.touch = screen.touch
	screen.overlay.active_pose = screen.panel.active
	screen.overlay.ui_scale = screen.ui_scale
	# Keep the on-screen keyboard on the field the pose paints (#201): a repaint
	# the field survives leaves the IME alone, and a pose that no longer paints it
	# puts the keyboard away.
	screen.focus.sync(screen)
	screen._last_mode = screen.mode
	screen.overlay.queue_redraw()
	screen.queue_redraw()

## Sheet chrome paint for the active pose (pinned doors live on their own node).
func paint(vp: Vector2) -> void:
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	screen.draw_rect(Rect2(Vector2.ZERO, vp), Color(0.008, 0.014, 0.018, 0.94))
	var pose: Array = LeagueView.pose(screen.mode)
	if pose.is_empty():
		return
	var owned: RefCounted = sheet(pose)
	var fonts: Dictionary = UiChrome.fonts()
	screen.hints.clear()
	Callable(owned, str(pose[3])).call(screen, vp, fonts, LeagueView.build(screen), screen.hints)
