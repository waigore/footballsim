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
	# The panel's two new readings (#103): Stats holds the played matchdays and
	# the podium door; Teams of Interest reads the shortlist and its search.
	if mode == LeagueScreen.MODE_STATS:
		var days: Array = []
		if season != null:
			var filters: Dictionary = screen.stats_filter
			for date in season.record.fixtures.dates():
				if str(filters.get("month", "")) != "" and not date.begins_with(str(filters["month"])):
					continue
				var rows: Array = season.record.fixtures.on(date, str(filters.get("league", "")))
				var done: int = 0
				var leagues: Array = []
				for fx in rows:
					if str(fx["status"]) == "played":
						if not _team_matches(season, fx, str(filters.get("team", ""))):
							continue
						done += 1
						var cid := str(fx.get("competition_id", ""))
						if not leagues.has(cid):
							leagues.append(cid)
				if done > 0:
					days.append({"date": date, "label": FixtureCalendar.day_label(date),
						"played": done, "matchday": int((rows[0] as Dictionary).get("matchday", 1)),
						"leagues": leagues})
		return {"name": state.get("name", ""), "complete": bool(state.get("complete", false)),
			"reports": days, "interests": state.get("interests", []),
			"competitions": state.get("competitions", []), "filters": screen.stats_filter,
			"leaders": _leaders(season, screen.stats_filter)}
	if mode == LeagueScreen.MODE_INTEREST:
		var marked: Array = state.get("interests", []) if season != null else []
		return {"query": screen.interest_query, "clubs": LeagueClubs.rows(marked),
			"results": LeagueClubs.search(screen.interest_query, marked)}
	if mode == LeagueScreen.MODE_TABLE:
		var tab := str(screen.book.table.league_tab)
		var comps: Array = state.get("competitions", [])
		if tab == "" or not _has_comp(comps, tab):
			tab = str(state.get("primary", "PL"))
		var tables: Dictionary = state.get("tables", {})
		var rules_by: Dictionary = state.get("rules_by", {})
		return {"table": tables.get(tab, state.get("table", [])),
			"rules": rules_by.get(tab, state.get("rules", rules)),
			"competitions": comps, "league_tab": tab,
			"name": state.get("name", ""), "date": state.get("date", ""),
			"interests": state.get("interests", [])}
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


static func _has_comp(comps: Array, competition_id: String) -> bool:
	for comp in comps:
		if str(comp.get("id", "")) == competition_id:
			return true
	return false

## The STATS team filter is a typed query: a fixture qualifies when either side
## matches it. An empty query matches every side.
static func _team_matches(season, fx: Dictionary, query: String) -> bool:
	var q := query.strip_edges().to_lower()
	if q == "":
		return true
	for key in ["home_club_id", "away_club_id"]:
		var club := PLRepository.shared().club(str(fx.get(key, "")))
		var hay := "%s %s" % [str(club.get("name", "")), str(club.get("abbr", ""))]
		if hay.to_lower().find(q) >= 0:
			return true
	return false

## The leader chart the STATS sheet draws: goals or assists, one league or all
## actives, and the same team query as the report list.
static func _leaders(season, filters: Dictionary) -> Array:
	if season == null:
		return []
	var teams: Array = []
	var q := str(filters.get("team", "")).strip_edges().to_lower()
	if q != "":
		for cid in PLRepository.shared().active_competition_ids():
			for id in PLRepository.shared().club_ids(str(cid)):
				var club := PLRepository.shared().club(str(id))
				var hay := "%s %s" % [str(club.get("name", "")), str(club.get("abbr", ""))]
				if hay.to_lower().find(q) >= 0:
					teams.append(str(id))
		if teams.is_empty():
			return []
	var rows := PLRepository.shared().sim_leaders(8, str(filters.get("league", "")),
		str(filters.get("stat", "goals")), teams)
	var stat := "assists" if str(filters.get("stat", "goals")) == "assists" else "goals"
	for row in rows:
		row["stat_value"] = int(row.get(stat, 0))
	return rows
