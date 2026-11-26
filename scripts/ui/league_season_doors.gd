class_name LeagueSeasonDoors
extends RefCounted

## The season's own doors: the clock (Continue and a fixture row), the calendar
## day a matchday opens on, and the shortlist a club row writes.
##
## Split out of `LeagueDoors` (the dispatch table is at its size budget) and
## written like `LeagueCalendar` / `LeagueSystemActions`: static helpers that
## work on the screen's own fields and hand anything the host owns — the match
## view, the report — back through the screen's doors. None of them repaints on
## their own; the press table asks for the repaint once the door has moved.

## Continue: settle the auto-played day, or open the pending watch first (#100).
static func continue_day(screen) -> void:
	if screen.season == null or screen.season.finishing:
		screen.refresh()
		return
	var result: Dictionary = screen.season.advance()
	var played: Array = result.get("played", [])
	if str(result.get("status", "")) == "complete" or bool(result.get("complete", false)):
		LeagueDoors.go(screen, screen.MODE_PODIUM)
		screen.month = LeagueMonth.state_month(screen.season, screen.month)
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
	screen.month = LeagueMonth.state_month(screen.season, screen.month)
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

## A fixture row: open its report, start a watched match, or flip the flag.
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

## A matchday opened from the Stats list: BACK returns there, not to the hub.
static func open_day(screen, date: String) -> void:
	if screen.season == null:
		return
	var rows: Array = []
	for fx in screen.season.record.fixtures.on(date):
		if str(fx["status"]) == "played":
			rows.append(screen.season.report(str(fx["id"])))
	LeagueDoors.go(screen, screen.MODE_REPORT)
	screen.roundup = rows
	screen.report = {}
	screen.report_back = screen.MODE_STATS

## Teams of Interest: add or remove a club in this save (#104). True when the
## save took the change, so the shortlist's search is cleared only on an add.
static func set_interest(screen, club_id: String, follow: bool) -> bool:
	if screen.season == null or club_id == "":
		return false
	if not screen.season.set_interest(club_id, follow):
		return false
	if follow:
		screen.interest_query = ""
	return true
