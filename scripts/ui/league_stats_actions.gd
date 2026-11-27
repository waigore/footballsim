class_name LeagueStatsActions
extends RefCounted


static func press(screen, id: String) -> bool:
	if id.begins_with("statsleague:"):
		screen.stats_filter["league"] = id.substr(12)
		screen.refresh()
		return true
	if id.begins_with("statsmonth:"):
		var base := str(screen.stats_filter.get("month", ""))
		if base == "":
			var date := str(screen.season.state().get("date", "")) if screen.season != null else ""
			base = date.substr(0, 7)
		if base != "":
			screen.stats_filter["month"] = LeagueMonth.shift(base, int(id.substr(11)))
		screen.refresh()
		return true
	if id.begins_with("statsstat:"):
		screen.stats_filter["stat"] = id.substr(10)
		screen.refresh()
		return true
	if id == "statsteam":
		screen.refresh()
		return true
	return false
