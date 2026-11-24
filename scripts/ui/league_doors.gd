class_name LeagueDoors
extends RefCounted

## Every door of the season surface: the key map, the press dispatch, and the
## season actions a press can reach.
##
## Split out of `LeagueScreen` (the scene script is at its size budget) and
## written like `LeagueCalendar` / `LeagueSystemActions`: static helpers that
## work on the screen's own public fields and doors, so the screen keeps its
## state and paint while its dispatch table lives here.
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
		continue_day(screen)
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
		if LeagueSheet.type_name_into(screen.wizard, code):
			screen.refresh()
			return true
	if screen.mode == screen.MODE_SYSTEM and LeagueSystemActions.type_name(screen, code):
		return true
	if screen.mode != screen.MODE_REPORT or code < KEY_1 or code > KEY_9:
		return false
	var want := code - KEY_1
	if not has_clip(screen, want):
		return false
	play_goal(screen, want)
	return true

# ----------------------------------------------------------------- press ---

## The whole press table. Ids are `sheet:payload`; the first arm that matches
## owns the press and the rest are skipped.
static func press(screen, id: String) -> void:
	if id == "":
		return
	if id.begins_with("match:"):
		screen.show_report(id.substr(6))
	elif id.begins_with("goal:"):
		play_goal(screen, int(id.substr(5)))
	elif id.begins_with("club:"):
		screen.club_requested.emit(id.substr(5))
	elif id.begins_with("toggle:"):
		toggle_fixture(screen, id.substr(7))
	elif id.begins_with("fixture:"):
		press_fixture(screen, id.substr(8))
	elif id.begins_with("open:"):
		open_save(screen, id.substr(5))
	elif id.begins_with("delete:"):
		delete_save(screen, id.substr(7))
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
		continue_day(screen)
	elif id == "suggest":
		screen.season.suggest()
		screen.refresh()
	elif id == "system":
		LeagueSystemActions.open(screen)
	elif id == "create":
		create(screen)
	elif id == "name":
		screen.refresh()

## Leave the current sheet. The System dialog gets first refusal (it swallows
## BACK while it is open); the menu-level sheets close the surface; every
## reading goes back to the hub.
static func back(screen) -> void:
	if LeagueSystemActions.back(screen):
		return
	if (screen.mode == screen.MODE_HUB or screen.mode == screen.MODE_WIZARD
			or screen.mode == screen.MODE_LOAD or screen.mode == screen.MODE_PODIUM):
		screen.close()
		return
	open_hub(screen)

# ----------------------------------------------------------------- doors ---

## Show the hub with its layout refreshed. The one place that sets the mode, so a
## door never forgets the repaint.
static func open_hub(screen) -> void:
	screen.mode = screen.MODE_HUB
	screen.refresh()

## The table reading, bound to this season's save so its sort and reading are the
## save's own. A surface with no season still opens the table (the strip paints
## empty) rather than guessing one.
static func open_table(screen) -> void:
	screen.mode = screen.MODE_TABLE
	screen.book.table.attach(screen.season.save if screen.season != null else null)
	screen.refresh()

static func open_calendar(screen) -> void:
	screen.mode = screen.MODE_CALENDAR
	LeagueCalendar.open(screen)

static func read_podium(screen) -> void:
	screen.mode = screen.MODE_PODIUM
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
	screen.season_opened.emit(created)
	screen.mode = screen.MODE_HUB
	screen.month = LeagueBook.state_month(screen.season, screen.month)
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

## Remove a save file. The open season unloads first when it is the same file, so
## a deleted save is never still bound in memory.
static func delete_save(screen, slug: String) -> void:
	if screen.season != null and screen.season.save.slug == slug:
		LeagueSystemActions.unload(screen)
	LeagueSave.remove(slug)
	screen.saves = LeagueSave.list()
	screen.refresh()

## Continue: settle the auto-played day, or open the pending watch first (#100).
static func continue_day(screen) -> void:
	if screen.season == null or screen.season.finishing:
		screen.refresh()
		return
	var result: Dictionary = screen.season.advance()
	var played: Array = result.get("played", [])
	if str(result.get("status", "")) == "complete" or bool(result.get("complete", false)):
		screen.mode = screen.MODE_PODIUM
		screen.month = LeagueBook.state_month(screen.season, screen.month)
		screen.refresh()
		return
	var pending: Array = result.get("pending", [])
	if not pending.is_empty():
		var watch: Dictionary = screen.season.start_watch(str(pending[0]["id"]))
		if not watch.is_empty():
			request_watch(screen, watch)
			return
	if not played.is_empty():
		screen.show_roundup(played)
		return
	screen.month = LeagueBook.state_month(screen.season, screen.month)
	screen.refresh()

## Hand a started watch to the host: it owns the match view and reports back.
static func request_watch(screen, watch: Dictionary) -> void:
	screen.match_requested.emit(str(watch["home"]), str(watch["away"]), str(watch["fixture_id"]))

## Flip the watch flag of a pending fixture. A played fixture has no watch flag.
static func toggle_fixture(screen, fixture_id: String) -> void:
	if screen.season == null:
		return
	var fx: Dictionary = screen.season.record.fixtures.one(fixture_id)
	if fx.is_empty() or str(fx["status"]) == "played":
		return
	screen.season.set_watch(fixture_id, int(fx["watched"]) != 1)
	screen.refresh()

## A calendar row: a played fixture opens its report, a watched one starts the
## match, and a pending one just flips its watch flag.
static func press_fixture(screen, fixture_id: String) -> void:
	if screen.season == null:
		return
	var fx: Dictionary = screen.season.record.fixtures.one(fixture_id)
	if fx.is_empty():
		return
	if str(fx["status"]) == "played":
		screen.show_report(fixture_id)
	elif int(fx["watched"]) == 1:
		var watch: Dictionary = screen.season.start_watch(fixture_id)
		if not watch.is_empty():
			request_watch(screen, watch)
	else:
		toggle_fixture(screen, fixture_id)

# ------------------------------------------------------------ highlights ---

## Play one goal of the report on screen. The host owns the viewer; the surface
## only names the fixture and the goal's ordinal.
static func play_goal(screen, index: int) -> void:
	if screen.mode != screen.MODE_REPORT or not has_clip(screen, index):
		return
	var fixture: Dictionary = screen.report.get("fixture", {})
	screen.goal_highlight_requested.emit(str(fixture.get("id", "")), index)

static func has_clip(screen, index: int) -> bool:
	for row in screen.report.get("highlights", []):
		if int(row.get("goal_index", -1)) == index:
			return true
	return false
