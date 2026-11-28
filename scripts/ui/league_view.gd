class_name LeagueView
extends RefCounted


static func pose_names() -> Dictionary:
	return {
		LeagueScreen.MODE_HUB: "fixtures", LeagueScreen.MODE_TABLE: "table",
		LeagueScreen.MODE_CALENDAR: "calendar", LeagueScreen.MODE_INTEREST: "interest",
		LeagueScreen.MODE_STATS: "stats", LeagueScreen.MODE_SYSTEM: "system",
		LeagueScreen.MODE_REPORT: "fixtures", LeagueScreen.MODE_PODIUM: "stats",
		LeagueScreen.MODE_EUROPE: "europe", LeagueScreen.MODE_EUROPE_STAGE: "europe",
		LeagueScreen.MODE_CUPS: "cups", LeagueScreen.MODE_CUP: "cups",
		LeagueScreen.MODE_BRACKET: "cups", LeagueScreen.MODE_CUP_DRAW: "cups",
	}


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
		LeagueScreen.MODE_STATS: ["stats", "layout", "draw_body", "draw_chrome"],
		LeagueScreen.MODE_INTEREST: ["interest", "layout", "draw_body", "draw_chrome"],
		LeagueScreen.MODE_EUROPE: ["europe", "layout", "draw_hub_body", "draw_hub_chrome"],
		LeagueScreen.MODE_EUROPE_STAGE: ["europe_stage", "layout", "draw_body", "draw_chrome"],
		LeagueScreen.MODE_CUPS: ["cups", "cups_layout", "draw_cups_body", "draw_cups_chrome"],
		LeagueScreen.MODE_CUP: ["cup", "cup_layout", "draw_cup_body", "draw_cup_chrome"],
		LeagueScreen.MODE_BRACKET: ["bracket", "bracket_layout", "draw_body", "draw_chrome"],
		LeagueScreen.MODE_CUP_DRAW: ["draw", "draw_layout", "draw_body", "draw_chrome"],
	}


static func pose(mode: String) -> Array:
	return sheets().get(mode, [])


static func panel_reading(mode: String) -> String:
	return str(pose_names().get(mode, ""))

static func build(screen) -> Dictionary:
	var mode: String = str(screen.mode)
	if mode == LeagueScreen.MODE_WIZARD or mode == LeagueScreen.MODE_LOAD:
		if mode == LeagueScreen.MODE_LOAD:
			return {"saves": screen.saves, "touch": bool(screen.touch)}

		var wiz: Dictionary = screen.wizard.duplicate()
		wiz["focus"] = str(screen.focus.kind)
		wiz["touch"] = bool(screen.touch)
		wiz["cup_countries"] = LeagueWizardActions.cup_countries(screen)
		wiz["cups_on"] = LeagueWizardActions.cups_on(screen)
		return wiz
	var season = screen.season
	var rules: Dictionary = season.rules if season != null else LeagueRules.defaults()
	var state: Dictionary = season.state() if season != null else {"rules": rules}
	if mode == LeagueScreen.MODE_CUPS:
		return {"cups": LeagueCupView.cups(screen.season), "touch": bool(screen.touch),
			"name": str(state.get("name", ""))}
	if mode == LeagueScreen.MODE_CUP or mode == LeagueScreen.MODE_BRACKET:
		return LeagueCupView.cup(screen.season, str(screen.cup_focus), str(screen.cups_round))
	if mode == LeagueScreen.MODE_CUP_DRAW:
		var drawn := LeagueCupView.draw(screen.season, str(screen.cup_focus),
			str(screen.cups_round))
		drawn["shown"] = int((screen.draw_state as Dictionary).get("shown", 0))
		drawn["touch"] = bool(screen.touch)
		return drawn
	if mode == LeagueScreen.MODE_SYSTEM:
		return LeagueSystemActions.view(screen)


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


			"played": int(state.get("played", 0)),
			"competitions": state.get("competitions", []), "filters": screen.stats_filter,
			"leaders": _leaders(season, screen.stats_filter), "touch": bool(screen.touch)}
	if mode == LeagueScreen.MODE_INTEREST:
		var marked: Array = state.get("interests", []) if season != null else []
		return {"query": screen.interest_query, "clubs": LeagueClubs.rows(marked),
			"results": LeagueClubs.search(screen.interest_query, marked),


			"focus": str(screen.focus.kind), "touch": bool(screen.touch)}
	if mode == LeagueScreen.MODE_EUROPE:
		var hub: Dictionary = LeagueEurope.hub(season.save if season != null else null)
		hub["touch"] = bool(screen.touch)
		hub["name"] = state.get("name", "")
		return hub
	if mode == LeagueScreen.MODE_EUROPE_STAGE:
		var comp := str(screen.europe_comp)
		var card: Dictionary = {}
		if season != null and comp != "":
			card = LeagueEurope.card(season.save, comp)
		var stage_view := {"card": card, "on": not card.is_empty(),
			"touch": bool(screen.touch), "rounds": [], "round": "", "table": [], "ties": []}
		if not card.is_empty():
			stage_view["rounds"] = LeagueEuropeTies.rounds(comp)
			var round_id: String = LeagueEuropeActions.round_of(screen)
			stage_view["round"] = round_id
			if round_id == LeagueUefa.LEAGUE_STAGE:
				stage_view["table"] = LeagueEurope.table(comp)
			else:
				stage_view["ties"] = LeagueEuropeTies.ties(comp, round_id)
		return stage_view
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
			"interests": state.get("interests", []),


			"touch": bool(screen.touch)}
	if mode == LeagueScreen.MODE_CALENDAR:
		return {"month": screen.month, "day": screen.day, "days": screen.days_cache,
			"day_fixtures": screen.day_fixtures, "interests": state.get("interests", []),
			"touch": bool(screen.touch)}
	if mode == LeagueScreen.MODE_REPORT:
		if not (screen.roundup as Array).is_empty():
			var first: Dictionary = screen.roundup[0]
			return {"roundup": screen.roundup, "interests": state.get("interests", []),
				"filters": screen.report_filter,
				"day": str(first["fixture"]["kickoff"]) if first.has("fixture") else "",
				"touch": bool(screen.touch)}
		var card: Dictionary = screen.report
		return {
			"fixture": card.get("fixture", {}), "events": card.get("events", []),
			"highlights": card.get("highlights", []),
			"day": str((card.get("fixture", {}) as Dictionary).get("kickoff", "")),
			"interests": state.get("interests", []), "touch": bool(screen.touch),
		}
	if mode == LeagueScreen.MODE_PODIUM:
		return {"summary": state.get("summary", {}), "name": state.get("name", ""),
			"table": state.get("table", []), "rules": state.get("rules", rules),
			"touch": bool(screen.touch)}
	var view: Dictionary = state.duplicate()


	view["touch"] = bool(screen.touch)
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


static func _leaders(season, filters: Dictionary) -> Array:
	if season == null:
		return []
	var teams: Array = []
	var q := str(filters.get("team", "")).strip_edges().to_lower()
	if q != "":
		for cid in PLCompetitions.active_ids():
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
