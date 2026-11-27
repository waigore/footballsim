class_name LeagueSeasonDoors
extends RefCounted


static func continue_day(screen) -> void:
	if screen.mode == screen.MODE_REPORT:
		leave_results(screen)
		return
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


static func leave_results(screen: LeagueScreen) -> void:
	var entry: Dictionary = screen.nav.pop()
	if entry.is_empty():
		screen.mode = screen.MODE_HUB
	else:
		LeagueNavStack.restore(screen, entry)
	if screen.season != null:


		screen.month = LeagueMonth.state_month(screen.season, screen.month)
	screen.refresh()


static func request_watch(screen, watch: Dictionary) -> void:
	screen.match_requested.emit(str(watch["home"]), str(watch["away"]), str(watch["fixture_id"]))


static func toggle_fixture(screen, fixture_id: String) -> void:
	if screen.season == null:
		return
	var fx: Dictionary = screen.season.record.fixtures.one(fixture_id)
	if fx.is_empty() or str(fx["status"]) == "played":
		return
	screen.season.set_watch(fixture_id, int(fx["watched"]) != 1)


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


static func set_interest(screen, club_id: String, follow: bool) -> bool:
	if screen.season == null or club_id == "":
		return false
	if not screen.season.set_interest(club_id, follow):
		return false
	if follow:
		screen.interest_query = ""
	return true
