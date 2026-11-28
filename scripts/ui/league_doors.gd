class_name LeagueDoors
extends RefCounted


const PAGE := 0.9

const STEP := 120.0

const EDGE := 1.0e7


static func key(screen, code: int) -> bool:
	if _typed(screen, code):
		return true
	if code == KEY_ESCAPE or code == KEY_BACKSPACE:
		back(screen)
		return true
	if screen.mode == screen.MODE_HUB and (code == KEY_ENTER or code == KEY_KP_ENTER):
		LeagueSeasonDoors.continue_day(screen)
		return true
	var page: float = screen.body.size.y * PAGE if screen.body != null else 0.0
	match code:
		KEY_UP, KEY_W:
			screen.scroll_by(-STEP)
		KEY_DOWN, KEY_S:
			screen.scroll_by(STEP)
		KEY_PAGEUP:
			screen.scroll_by(-page)
		KEY_PAGEDOWN:
			screen.scroll_by(page)
		KEY_HOME:
			screen.scroll_by(-EDGE)
		KEY_END:
			screen.scroll_by(EDGE)
		_:
			return false
	return true


static func text_key(screen, code: int, unicode: int) -> bool:
	if unicode <= 0 or LeagueTextField.accepts(LeagueTextField.char_of(code)):
		return false
	return _typed(screen, 0, char(unicode))


static func _typed(screen, code: int, ch: String = "") -> bool:
	if screen.mode == screen.MODE_WIZARD:
		if _edit(screen.wizard, code, ch):
			screen.refresh()
			return true
	if screen.mode == screen.MODE_SYSTEM and LeagueSystemActions.type_name(screen, code, ch):
		return true

	if screen.mode == screen.MODE_INTEREST:
		var query := str(screen.interest_query)
		var typed: Array = LeagueTextField.type_char(query, ch) if ch != "" \
			else LeagueTextField.type_name(query, code)
		if bool(typed[0]):
			screen.interest_query = str(typed[1]).to_lower()
			screen.refresh()
			return true

	if screen.mode == screen.MODE_STATS:
		var typed_stats: Array = LeagueTextField.type_name(str(screen.stats_filter.get("team", "")), code)
		if bool(typed_stats[0]):
			screen.stats_filter["team"] = str(typed_stats[1])
			screen.refresh()
			return true
	if screen.mode != screen.MODE_REPORT or code < KEY_1 or code > KEY_9:
		return false
	var want := code - KEY_1
	if not LeagueGoalDoors.has_clip(screen, want):
		return false
	LeagueGoalDoors.play(screen, want)
	return true


static func _edit(state: Dictionary, code: int, ch: String) -> bool:
	return LeagueTextField.type_char_into(state, ch) if ch != "" \
		else LeagueTextField.type_name_into(state, code)


static func press(screen, id: String) -> void:
	if id == "":
		return


	if LeagueFieldFocus.kind_of(id) != "":
		LeagueFieldFocus.press(screen, LeagueFieldFocus.kind_of(id))
		screen.refresh()
		return
	screen.focus.blur()


	if id == "delete_yes":
		screen.delete.answer(screen)
		return
	if id == "delete_no":
		screen.delete.cancel(screen)
		return
	if LeagueStatsActions.press(screen, id):
		return
	if LeagueReportActions.press(screen, id):
		return
	if LeagueCupDoors.press(screen, id):
		return
	if LeagueEuropeActions.press(screen, id):
		return
	if id.begins_with("match:"):
		screen.show_report(id.substr(6))
	elif id.begins_with("goal:"):
		LeagueGoalDoors.play(screen, int(id.substr(5)))
	elif id.begins_with("club:"):
		screen.club_requested.emit(id.substr(5))
	elif id.begins_with("toggle:"):
		LeagueSeasonDoors.toggle_fixture(screen, id.substr(7))
		screen.refresh()
	elif id.begins_with("fixture:"):
		LeagueSeasonDoors.press_fixture(screen, id.substr(8))
	elif id.begins_with("open:"):
		open_save(screen, id.substr(5))
	elif id.begins_with("delete:"):
		screen.delete.ask_from(screen.saves, id.substr(7))
		screen.refresh()
	elif id.begins_with("wleague:"):
		LeagueWizardActions.toggle_league(screen, id.substr(8))
	elif id.begins_with("wcups:"):
		LeagueWizardActions.toggle_cups(screen, id.substr(6))
	elif id == "uefa":
		screen.wizard["uefa"] = not bool(screen.wizard.get("uefa", false))
		screen.refresh()
	elif id.begins_with("mode:"):
		screen.wizard["calendar_mode"] = id.substr(5)
		screen.refresh()
	elif id.begins_with("adv:"):
		screen.wizard["advance_mode"] = id.substr(4)
		screen.refresh()
	elif id.begins_with("day:"):
		LeagueCalendar.pick(screen, id.substr(4))
	elif id.begins_with("month:"):
		LeagueCalendar.shift(screen, int(id.substr(6)))
	elif id.begins_with("tbl:"):
		if screen.season != null and screen.book.table.press(id, screen.season.save):
			screen.refresh()
	elif id == "panel":
		screen.panel.open()
		screen.overlay.queue_redraw()
	elif id == "panel:close":
		screen.panel.close()
		screen.overlay.queue_redraw()
	elif id.begins_with("nav:"):
		LeaguePanelDoors.nav(screen, id.substr(4))
	elif id.begins_with("stats:"):
		LeaguePanelDoors.stats(screen, id)
	elif id.begins_with("statsday:"):
		LeagueSeasonDoors.open_day(screen, id.substr(9))
		screen.refresh()
	elif id.begins_with("interest:add:"):
		_set_interest(screen, id.substr(13), true)
	elif id.begins_with("interest:remove:"):
		_set_interest(screen, id.substr(16), false)
	elif id.begins_with("sys:"):
		LeagueSystemActions.act(screen, id)
	elif id == "back":
		back(screen)
	elif id == "menu":
		screen.close()
	elif id == "table":
		open_table(screen)
	elif id == "calendar":
		open_calendar(screen)
	elif id == "podium":
		read_podium(screen)
	elif id == "continue":
		LeagueSeasonDoors.continue_day(screen)
	elif id == "suggest":
		screen.season.suggest()
		screen.refresh()
	elif id == "system":
		LeagueSystemActions.open(screen)
	elif id == "create":
		create(screen)


static func back(screen) -> void:

	screen.focus.blur()


	if screen.delete_confirm_open():
		screen.delete.cancel(screen)
		return
	if screen.mode == screen.MODE_WIZARD:
		screen.close()
		return
	if screen.mode == screen.MODE_LOAD:


		if str(screen.load_from) == "system" and not screen.nav.is_empty():
			LeagueNavStack.restore(screen, screen.nav.pop())
			return
		screen.close()
		return
	if screen.season == null:
		screen.close()
		return
	if screen.mode == screen.MODE_CUP_DRAW:
		LeagueCupDoors.leave_draw(screen)
	if screen.nav.is_empty():
		return
	LeagueNavStack.restore(screen, screen.nav.pop())


static func can_back(screen) -> bool:
	if screen.mode == screen.MODE_WIZARD or screen.mode == screen.MODE_LOAD:
		return true
	if screen.season == null:
		return true
	return not screen.nav.is_empty()


static func open_hub(screen) -> void:
	if screen.mode != screen.MODE_HUB:
		screen.push_page()
	screen.mode = screen.MODE_HUB
	screen.refresh()


static func go(screen, next: String) -> void:
	if next != screen.mode:
		screen.push_page()
	screen.mode = next


static func open_table(screen) -> void:
	go(screen, screen.MODE_TABLE)
	LeaguePanelDoors.attach_table(screen)
	screen.refresh()

static func open_calendar(screen) -> void:
	go(screen, screen.MODE_CALENDAR)
	LeagueCalendar.open(screen)

static func read_podium(screen) -> void:
	go(screen, screen.MODE_PODIUM)
	screen.refresh()


static func create(screen) -> void:
	var comps: Array = screen.wizard.get("competitions", ["PL"])
	if comps.is_empty():
		comps = ["PL"]
	var name := LeagueStartSheet.save_name(str(screen.wizard.get("name", "")))
	var countries: Array = LeagueWizardActions.cups_on(screen)
	var created: LeagueSeason = LeagueSeason.create(name,
		str(screen.wizard["calendar_mode"]), str(screen.wizard["advance_mode"]), 0, comps,
		not countries.is_empty(), countries, bool(screen.wizard.get("uefa", false)))
	if created == null:
		screen.wizard["error"] = "The season could not be created."
		screen.refresh()
		return
	screen.season = created

	screen.nav.clear()
	screen.season_opened.emit(created)
	screen.mode = screen.MODE_HUB
	screen.month = LeagueMonth.state_month(screen.season, screen.month)
	screen.refresh()


static func open_save(screen, slug: String) -> void:
	LeagueSystemActions.unload(screen)
	var opened: LeagueSeason = LeagueSeason.open(slug)
	if opened == null:
		screen.wizard["error"] = "That save could not be opened."
		screen.mode = screen.MODE_WIZARD
		screen.refresh()
		return
	screen.open_season(opened, str(opened.state().get("status", "")) == "complete")


static func delete_save(screen, slug: String) -> void:
	if screen.season != null and screen.season.save.slug == slug:
		LeagueSystemActions.unload(screen)
	LeagueSaveCatalog.remove(slug)
	screen.saves = LeagueSaveCatalog.list()
	screen.refresh()


static func _set_interest(screen, club_id: String, follow: bool) -> void:
	if LeagueSeasonDoors.set_interest(screen, club_id, follow):
		screen.refresh()
