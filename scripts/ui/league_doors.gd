class_name LeagueDoors
extends RefCounted

## Every door of the season surface: the key map, the press dispatch, and the
## page walk a press can take.
##
## Split out of `LeagueScreen` (the scene script is at its size budget) and
## written like `LeagueCalendar` / `LeagueSystemActions`: static helpers that
## work on the screen's own public fields and doors, so the screen keeps its
## state and paint while its dispatch table lives here.
##
## The table stays a table: this module only routes. A door that reaches into
## the season lives in `LeagueSeasonDoors` (Continue, fixture rows, the calendar
## day, the shortlist), a report's goal doors in `LeagueGoalDoors`, the panel's
## destinations and the Stats reading in `LeaguePanelDoors`, and the System
## dialog in `LeagueSystemActions`, so no one file carries both the dispatch and
## the actions a door performs.
##
## The screen's `click()` and `key()` are one-line forwarders, so the host and the
## suite keep pressing the same surface. Row doors never repaint on their own:
## each one either moves the pose (and refreshes) or emits a request the host
## answers.

## One page of the scroll window, in keys.
const PAGE := 0.9
## A key nudge: a few readable rows.
const STEP := 120.0
## HOME / END walk the whole sheet; the body clamps to its own extent.
const EDGE := 1.0e7

# ------------------------------------------------------------------ keys ---

## Run the key map against the screen. True when the key belonged to the surface
## and the caller should not pass it on.
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

## Text-entry sheets take their keys first: the wizard's name field, the System
## dialog's Save As name field, and the report's numbered goal doors. A key they
## do not own falls through to the map (so BACKSPACE on an empty field still
## leaves the sheet, and a digit with no clip stays a no-op).
static func _typed(screen, code: int) -> bool:
	if screen.mode == screen.MODE_WIZARD:
		if LeagueTextField.type_name_into(screen.wizard, code):
			screen.refresh()
			return true
	if screen.mode == screen.MODE_SYSTEM and LeagueSystemActions.type_name(screen, code):
		return true
	# The shortlist's search field takes printable keys while the list is open.
	if screen.mode == screen.MODE_INTEREST:
		var typed: Array = LeagueTextField.type_name(str(screen.interest_query), code)
		if bool(typed[0]):
			screen.interest_query = str(typed[1]).to_lower()
			screen.refresh()
			return true
	if screen.mode != screen.MODE_REPORT or code < KEY_1 or code > KEY_9:
		return false
	var want := code - KEY_1
	if not LeagueGoalDoors.has_clip(screen, want):
		return false
	LeagueGoalDoors.play(screen, want)
	return true

# ----------------------------------------------------------------- press ---

## The whole press table. Ids are `sheet:payload`; the first arm that matches
## owns the press and the rest are skipped.
static func press(screen, id: String) -> void:
	if id == "":
		return
	# The delete confirmation's two doors answer before the sheet does. They carry
	# no `delete:` prefix, so no save slug can ever be mistaken for an answer.
	if id == "delete_yes":
		screen.delete.answer(screen)
		return
	if id == "delete_no":
		screen.delete.cancel(screen)
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
	elif id == "name":
		screen.refresh()

## Leave the current page. The season walks its own history (#169): BACK is the
## previous page, at the root it does nothing, and the main menu is reached only
## through System → MAIN MENU. The menu-level sheets (New League, Load) are not
## pages of a season: their BACK returns to the caller that opened them.
static func back(screen) -> void:
	# The delete confirmation is the top-most surface: BACK puts it away and
	# leaves the sheet it was raised over untouched.
	if screen.delete_confirm_open():
		screen.delete.cancel(screen)
		return
	if screen.mode == screen.MODE_WIZARD:
		screen.close()
		return
	if screen.mode == screen.MODE_LOAD:
		# A load list opened over the season is a page of it; one opened from the
		# menu returns to the menu.
		if str(screen.load_from) == "system" and not screen.nav.is_empty():
			LeagueNavStack.restore(screen, screen.nav.pop())
			return
		screen.close()
		return
	if screen.season == null:
		screen.close()
		return
	# At the root BACK is disabled, not a trapdoor: nothing behind it to reach.
	if screen.nav.is_empty():
		return
	LeagueNavStack.restore(screen, screen.nav.pop())

## True while the BACK door has a page behind it. The sheet paints the door
## dimmed when it does not, so a disabled BACK is visible, never hidden.
static func can_back(screen) -> bool:
	if screen.mode == screen.MODE_WIZARD or screen.mode == screen.MODE_LOAD:
		return true
	if screen.season == null:
		return true
	return not screen.nav.is_empty()

# ----------------------------------------------------------------- doors ---

## Show the hub with its layout refreshed. The one place that sets the mode, so a
## door never forgets the repaint.
static func open_hub(screen) -> void:
	if screen.mode != screen.MODE_HUB:
		screen.push_page()
	screen.mode = screen.MODE_HUB
	screen.refresh()

## Walk forward one page: remember where the player was, then show the next
## pose. A press that leaves the pose where it is never grows the history.
static func go(screen, next: String) -> void:
	if next != screen.mode:
		screen.push_page()
	screen.mode = next

## The table reading, bound to this season's save so its sort and reading are the
## save's own. A surface with no season still opens the table (the strip paints
## empty) rather than guessing one.
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

## New season from the wizard: the name, the calendar and the clock the player
## chose. A refusal stays on the wizard with its message.
static func create(screen) -> void:
	var created: LeagueSeason = LeagueSeason.create(str(screen.wizard["name"]), str(screen.wizard["calendar_mode"]),
		str(screen.wizard["advance_mode"]), 0)
	if created == null:
		screen.wizard["error"] = "The season could not be created."
		screen.refresh()
		return
	screen.season = created
	# A new season starts a new history.
	screen.nav.clear()
	screen.season_opened.emit(created)
	screen.mode = screen.MODE_HUB
	screen.month = LeagueMonth.state_month(screen.season, screen.month)
	screen.refresh()

## Load replaces the season outright: the old save, its ledger and every cached
## sheet reading go before the new file is bound, so nothing leaks across.
static func open_save(screen, slug: String) -> void:
	LeagueSystemActions.unload(screen)
	var opened: LeagueSeason = LeagueSeason.open(slug)
	if opened == null:
		screen.wizard["error"] = "That save could not be opened."
		screen.mode = screen.MODE_WIZARD
		screen.refresh()
		return
	screen.open_season(opened, str(opened.state().get("status", "")) == "complete")

## Remove a save file once the confirmation has been answered. The open season
## unloads first when it is the same file, so a deleted save is never still bound
## in memory.
static func delete_save(screen, slug: String) -> void:
	if screen.season != null and screen.season.save.slug == slug:
		LeagueSystemActions.unload(screen)
	LeagueSave.remove(slug)
	screen.saves = LeagueSave.list()
	screen.refresh()

## Teams of Interest from the list: add or remove a club in this save (#104).
## The list repaints only when the save took the change.
static func _set_interest(screen, club_id: String, follow: bool) -> void:
	if LeagueSeasonDoors.set_interest(screen, club_id, follow):
		screen.refresh()
