class_name LeagueCalendar
extends RefCounted


static func open(screen) -> void:
	screen.days_cache = {}
	var season = screen.season
	if season != null:
		for fx in season.record.fixtures.all():
			var date: String = str(fx["kickoff"])
			if not screen.days_cache.has(date):
				screen.days_cache[date] = {"n": 0, "played": 0, "by_league": {}}
			var info: Dictionary = screen.days_cache[date]
			info["n"] = int(info["n"]) + 1
			var cid := str(fx.get("competition_id", ""))
			if not (info["by_league"] as Dictionary).has(cid):
				info["by_league"][cid] = {"n": 0, "played": 0}
			var mine: Dictionary = info["by_league"][cid]
			mine["n"] = int(mine["n"]) + 1
			if str(fx["status"]) == "played":
				info["played"] = int(info["played"]) + 1
				mine["played"] = int(mine["played"]) + 1
		screen.month = LeagueMonth.state_month(season, screen.month)
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


static func shift(screen, delta: int) -> void:
	screen.month = LeagueMonth.shift(screen.month, delta)
	var keys: Array = screen.days_cache.keys()
	keys.sort()
	var chosen: String = str(screen.month) + "-01"
	for date in keys:
		if str(date).begins_with(screen.month):
			chosen = str(date)
			break
	pick(screen, chosen)


static func pick(screen, date: String) -> void:
	screen.day = date
	screen.day_fixtures = []
	if screen.season != null:
		for fx in screen.season.record.fixtures.on(date):
			if str(fx["status"]) == "played":
				fx["events"] = screen.season.record.report.events(str(fx["id"]))
			screen.day_fixtures.append(fx)
	screen.refresh()
