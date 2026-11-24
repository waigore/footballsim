class_name LeagueView
extends RefCounted

## What one league pose shows: the season clock, the day's fixtures, the table,
## the report on screen or the System dialog's own state, turned into the plain
## dictionary the sheet layouts read.
##
## Split out of the modal screen so the screen stays inside its size budget. The
## builder works on the screen's own fields, exactly like `LeagueCalendar`, so the
## screen and its tests keep reading the same state they always did.

static func build(screen) -> Dictionary:
	var mode: String = str(screen.mode)
	if mode == LeagueScreen.MODE_WIZARD or mode == LeagueScreen.MODE_LOAD:
		return screen.wizard if mode == LeagueScreen.MODE_WIZARD else {"saves": screen.saves}
	var season = screen.season
	var rules: Dictionary = season.rules if season != null else LeagueRules.defaults()
	var state: Dictionary = season.state() if season != null else {"rules": rules}
	if mode == LeagueScreen.MODE_SYSTEM:
		return LeagueSystemActions.view(screen)
	if mode == LeagueScreen.MODE_TABLE:
		return {"table": state.get("table", []), "rules": state.get("rules", rules),
			"name": state.get("name", ""), "date": state.get("date", ""),
			"interests": state.get("interests", [])}
	if mode == LeagueScreen.MODE_CALENDAR:
		return {"month": screen.month, "day": screen.day, "days": screen.days_cache,
			"day_fixtures": screen.day_fixtures}
	if mode == LeagueScreen.MODE_REPORT:
		if not (screen.roundup as Array).is_empty():
			var first: Dictionary = screen.roundup[0]
			return {"roundup": screen.roundup,
				"day": str(first["fixture"]["kickoff"]) if first.has("fixture") else ""}
		var card: Dictionary = screen.report
		return {
			"fixture": card.get("fixture", {}), "events": card.get("events", []),
			"highlights": card.get("highlights", []),
			"day": str((card.get("fixture", {}) as Dictionary).get("kickoff", "")),
		}
	if mode == LeagueScreen.MODE_PODIUM:
		return {"summary": state.get("summary", {}), "name": state.get("name", ""),
			"table": state.get("table", []), "rules": state.get("rules", rules)}
	var view: Dictionary = state.duplicate()
	if season != null:
		view["plan"] = season.plan()
		view["can_suggest"] = bool(view.get("can_suggest", false))
		view["settling"] = season.finishing
	else:
		view["plan"] = []
	view["screen"] = mode
	return view
