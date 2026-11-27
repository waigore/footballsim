class_name LeagueScreenPages
extends RefCounted


var screen = null

func _init(host: Control) -> void:
	screen = host


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


func push_page() -> void:
	screen.nav.push(LeagueNavStack.snapshot(screen))

func close() -> void:
	screen.visible = false
	screen.mode = LeagueScreen.MODE_HUB
	screen.delete.clear()

	screen.focus.blur()

	screen.nav.clear()
	screen.closed.emit()


func open_save(slug: String) -> void:
	LeagueDoors.open_save(screen, slug)


func bottom_bar(items: Array) -> float:
	if screen.mode == LeagueScreen.MODE_TABLE:
		return LeagueChrome.BAR_H
	if screen.mode == LeagueScreen.MODE_WIZARD:
		return LeagueStartSheet.bar_of(items)
	return 0.0


func sheet(pose: Array) -> RefCounted:
	match str(pose[0]):
		"start":
			return screen.start
		"book":
			return screen.book
		"system":
			return screen.system
		"stats":
			return screen.sheet_stats
		"interest":
			return screen.sheet_interest
	return screen.hub


func refresh() -> void:
	var vp: Vector2 = screen.design_vp()
	var view: Dictionary = LeagueView.build(screen)

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


	var can_back: bool = LeagueDoors.can_back(screen)
	for item in items:
		if str(item.get("id", "")) == "back":
			item["disabled"] = not can_back
	var content: Array = screen.body.set_sheet(items, vp, screen.mode != screen._last_mode, bottom_bar(items))
	screen.body.cue = screen.mode == LeagueScreen.MODE_WIZARD
	var fonts: Dictionary = UiChrome.fonts()
	screen.body.painter = Callable(owned, str(pose[2])).bind(vp, fonts, content, view)


	screen.pinned.fonts = fonts
	screen.pinned.cache = screen.hub.cache
	screen.pinned.size = vp
	screen.pinned.queue_redraw()
	screen.body.frozen = screen.delete_confirm_open()
	screen.panel.active = LeagueView.panel_reading(screen.mode)


	if screen.panel.active == "":
		screen.panel.close()
		screen.panel.settle()


	screen.panel.touch = screen.touch
	screen.overlay.active_pose = screen.panel.active
	screen.overlay.ui_scale = screen.ui_scale


	screen.focus.sync(screen)
	screen._last_mode = screen.mode
	screen.overlay.queue_redraw()
	screen.queue_redraw()


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
