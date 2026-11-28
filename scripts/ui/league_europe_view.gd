class_name LeagueEuropeView
extends RefCounted


static func hub(screen) -> Dictionary:
	var season = screen.season
	var save: LeagueSave = season.save if season != null else null
	var ids := LeagueEurope.active_ids(save) if save != null else []
	var date := save.current_date() if save != null else ""
	var plan: Array = []
	if season != null:
		for fx in season.plan():
			if ids.has(str(fx.get("competition_id", ""))):
				plan.append(fx)
	var cards: Array = []
	for cid in ids:
		cards.append(LeagueEurope.card(save, str(cid)))
	return {"date": date, "day": FixtureCalendar.day_label(date) if date != "" else "",
		"cards": cards, "tonight": plan,
		"draws": LeagueEurope.pending_draws(save) if save != null else [],
		"interests": season.record.interest.interests() if season != null else [],
		"touch": bool(screen.touch)}


static func stage(screen) -> Dictionary:
	var season = screen.season
	var save: LeagueSave = season.save if season != null else null
	var ids := LeagueEurope.active_ids(save) if save != null else []
	var comp := str(screen.europe.get("comp", ""))
	if comp == "" or not ids.has(comp):
		comp = str(ids[0]) if not ids.is_empty() else ""
	var stage := LeagueEurope.stage_of(comp)
	var tab := str(screen.europe.get("tab", ""))
	if tab == "":
		tab = "table" if stage == LeagueUefa.LEAGUE_STAGE else "qualifying"
		if LeagueEurope.KO_ROUNDS.has(stage):
			tab = "bracket"
	var comps: Array = []
	for cid in ids:
		var row := PLRepository.shared().competition(str(cid))
		comps.append({"id": str(cid), "short": str(row.get("short_name", cid))})
	var tabs: Array = [
		{"id": "qualifying", "label": "QUALIFYING"},
		{"id": "table", "label": "LEAGUE PHASE"},
		{"id": "bracket", "label": "BRACKET"},
	]
	return {"comp": comp, "short": _short(comp), "stage": LeagueEurope.stage_label(comp),
		"tab": tab, "comps": comps, "tabs": tabs, "touch": bool(screen.touch),
		"table": PLRepository.shared().table(comp) if season != null else [],
		"qualifying": LeagueEuropeTies.qualifying(comp) if season != null else [],
		"bracket": LeagueEuropeTies.bracket(comp) if season != null else [],
		"round": str(screen.europe.get("round", "")),
		"interests": season.record.interest.interests() if season != null else []}


static func draw(screen) -> Dictionary:
	var season = screen.season
	var save: LeagueSave = season.save if season != null else null
	var competition_id := str(screen.europe_draw.get("competition", ""))
	var round_id := str(screen.europe_draw.get("round", ""))
	var out: Dictionary = LeagueEurope.draw_data(save, competition_id, round_id) \
		if save != null else {}
	out["revealed"] = int(screen.europe_draw.get("revealed", 0))
	out["done"] = bool(screen.europe_draw.get("done", false))
	out["touch"] = bool(screen.touch)
	out["stage"] = LeagueEurope.stage_label(competition_id)
	return out


static func _short(competition_id: String) -> String:
	return str(PLRepository.shared().competition(competition_id).get("short_name",
		competition_id))
