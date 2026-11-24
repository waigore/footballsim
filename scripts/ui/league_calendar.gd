class_name LeagueCalendar
extends RefCounted

## The month grid a season's calendar screen shows: which days hold fixtures,
## how many of them are played, and which day is open under the grid.
##
## Split out of the modal screen so its state machine stays inside the size
## budget. The helpers work on the screen's own fields — `month`, `day`,
## `days_cache` and `day_fixtures` — so the screen (and its tests) keep reading
## the same state they always did.

## Build the day index for the season's month and open a day in it: the clock's
## own day when it falls inside the month, else the first day with fixtures.
static func open(screen) -> void:
	screen.days_cache = {}
	var season = screen.season
	if season != null:
		for fx in season.record.fixtures.all():
			var date: String = str(fx["kickoff"])
			if not screen.days_cache.has(date):
				screen.days_cache[date] = {"n": 0, "played": 0}
			screen.days_cache[date]["n"] = int(screen.days_cache[date]["n"]) + 1
			if str(fx["status"]) == "played":
				screen.days_cache[date]["played"] = int(screen.days_cache[date]["played"]) + 1
		screen.month = LeagueBook.state_month(season, screen.month)
	var chosen: String = str(screen.month) + "-01"
	if season != null:
		var current: String = str(season.state().get("date", ""))
		if current.begins_with(screen.month):
			chosen = current
		else:
			var keys: Array = screen.days_cache.keys()
			keys.sort()
			for date in keys:
				if str(date).begins_with(screen.month):
					chosen = str(date)
					break
	pick(screen, chosen)

## Move the grid a month and open the first day of the new month that has a
## fixture (or its first day when the month is empty).
static func shift(screen, delta: int) -> void:
	screen.month = LeagueBook.shift_month(screen.month, delta)
	var keys: Array = screen.days_cache.keys()
	keys.sort()
	var chosen: String = str(screen.month) + "-01"
	for date in keys:
		if str(date).begins_with(screen.month):
			chosen = str(date)
			break
	pick(screen, chosen)

## Open one day: the fixtures that day, and the screen repaint.
static func pick(screen, date: String) -> void:
	screen.day = date
	screen.day_fixtures = []
	if screen.season != null:
		for fx in screen.season.record.fixtures.on(date):
			screen.day_fixtures.append(fx)
	screen.refresh()
