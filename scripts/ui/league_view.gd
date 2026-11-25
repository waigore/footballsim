class_name LeagueView
extends RefCounted

## What one league pose shows: the season clock, the day's fixtures, the table,
## the report on screen or the System dialog's own state, turned into the plain
## dictionary the sheet layouts read.
##
## Split out of the modal screen so the screen stays inside its size budget. The
## builder works on the screen's own fields, exactly like `LeagueCalendar`, so the
## screen and its tests keep reading the same state they always did.

## Panel destination (LeaguePanel.pose) for each pose on screen.
static func pose_names() -> Dictionary:
	return {
		LeagueScreen.MODE_HUB: "fixtures", LeagueScreen.MODE_TABLE: "table",
		LeagueScreen.MODE_CALENDAR: "calendar", LeagueScreen.MODE_INTEREST: "interest",
		LeagueScreen.MODE_STATS: "stats", LeagueScreen.MODE_SYSTEM: "system",
		LeagueScreen.MODE_REPORT: "fixtures", LeagueScreen.MODE_PODIUM: "stats",
	}

## The sheet that owns a pose, in a fixed order: its name on the screen, the
## layout it answers, the body it paints and the chrome it paints around it. One
## table, read by `pose`, so the screen never decodes a dispatch of its own.
static func sheets() -> Dictionary:
	return {
		LeagueScreen.MODE_HUB: ["hub", "hub_layout", "draw_hub_body", "draw_hub_chrome"],
		LeagueScreen.MODE_WIZARD: ["start", "wizard_layout", "draw_wizard_body", "draw_wizard_chrome"],
		LeagueScreen.MODE_LOAD: ["start", "load_layout", "draw_load_body", "draw_load_chrome"],
		LeagueScreen.MODE_TABLE: ["book", "table_layout", "draw_table_body", "draw_table_chrome"],
		LeagueScreen.MODE_CALENDAR: ["book", "calendar_layout", "draw_calendar_body",
			"draw_calendar_chrome"],
		LeagueScreen.MODE_REPORT: ["book", "report_layout", "draw_report_body", "draw_report_chrome"],
		LeagueScreen.MODE_PODIUM: ["book", "podium_layout", "draw_podium_body", "draw_podium_chrome"],
		LeagueScreen.MODE_SYSTEM: ["system", "layout", "draw_body", "draw_chrome"],
		LeagueScreen.MODE_STATS: ["extra", "stats_layout", "draw_stats_body", "draw_stats_chrome"],
		LeagueScreen.MODE_INTEREST: ["extra", "interest_layout", "draw_interest_body",
			"draw_interest_chrome"],
	}

## The dispatch of one pose: `[sheet, layout, body, chrome]`, empty for a mode
## no sheet owns.
static func pose(mode: String) -> Array:
	return sheets().get(mode, [])

## The panel's reading for a pose, or "" when the panel has no door for it.
static func panel_reading(mode: String) -> String:
	return str(pose_names().get(mode, ""))

static func build(screen) -> Dictionary:
	var mode: String = str(screen.mode)
	if mode == LeagueScreen.MODE_WIZARD or mode == LeagueScreen.MODE_LOAD:
		if mode == LeagueScreen.MODE_LOAD:
			return {"saves": screen.saves}
		# The wizard's own state, plus where the keyboard is (#201).
		var wiz: Dictionary = screen.wizard.duplicate()
		wiz["focus"] = str(screen.focus.kind)
		return wiz
	var season = screen.season
	var rules: Dictionary = season.rules if season != null else LeagueRules.defaults()
	var state: Dictionary = season.state() if season != null else {"rules": rules}
	if mode == LeagueScreen.MODE_SYSTEM:
		return LeagueSystemActions.view(screen)
	# The panel's two new readings (#103): Stats holds the played matchdays and
	# the podium door; Teams of Interest reads the shortlist and its search.
	if mode == LeagueScreen.MODE_STATS:
		var days: Array = []
		if season != null:
			for date in season.record.fixtures.dates():
				var rows: Array = season.record.fixtures.on(date)
				var done: int = 0
				for fx in rows:
					if str(fx["status"]) == "played":
						done += 1
				if done > 0:
					days.append({"date": date, "label": FixtureCalendar.day_label(date),
						"played": done, "matchday": int((rows[0] as Dictionary).get("matchday", 1))})
		return {"name": state.get("name", ""), "complete": bool(state.get("complete", false)),
			"reports": days, "interests": state.get("interests", [])}
	if mode == LeagueScreen.MODE_INTEREST:
		var marked: Array = state.get("interests", []) if season != null else []
		return {"query": screen.interest_query, "clubs": LeagueClubs.rows(marked),
			"results": LeagueClubs.search(screen.interest_query, marked),
			# Where the on-screen keyboard is (#201), so the search field can
			# paint its caret only while it owns the keyboard.
			"focus": str(screen.focus.kind)}
	if mode == LeagueScreen.MODE_TABLE:
		return {"table": state.get("table", []), "rules": state.get("rules", rules),
			"name": state.get("name", ""), "date": state.get("date", ""),
			"interests": state.get("interests", []),
			# A touch sheet lays thumb-sized rows and headers (#204); a desktop
			# sheet keeps its dense reading, so the pose carries the device.
			"touch": bool(screen.touch)}
	if mode == LeagueScreen.MODE_CALENDAR:
		return {"month": screen.month, "day": screen.day, "days": screen.days_cache,
			"day_fixtures": screen.day_fixtures, "interests": state.get("interests", [])}
	if mode == LeagueScreen.MODE_REPORT:
		if not (screen.roundup as Array).is_empty():
			var first: Dictionary = screen.roundup[0]
			return {"roundup": screen.roundup, "interests": state.get("interests", []),
				"day": str(first["fixture"]["kickoff"]) if first.has("fixture") else ""}
		var card: Dictionary = screen.report
		return {
			"fixture": card.get("fixture", {}), "events": card.get("events", []),
			"highlights": card.get("highlights", []),
			"day": str((card.get("fixture", {}) as Dictionary).get("kickoff", "")),
			"interests": state.get("interests", []),
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
