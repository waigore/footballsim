class_name LeagueSeasonState
extends RefCounted


static func build(season: LeagueSeason) -> Dictionary:
	if season == null or season.save == null or season.record == null:
		return {}
	var save: LeagueSave = season.save
	save.reload()
	season.rules_by = save.rules_by
	season.rules = save.rules
	var date := save.current_date()
	var complete := save.status() == "complete"
	var comps: Array = []
	var tables := {}
	var gameweeks := {}
	for cid in save.actives:
		var rows := season.record.fixtures.on(date, str(cid))
		var gw := save.matchday()
		if not rows.is_empty():
			gw = int(rows[0]["matchday"])
		gameweeks[str(cid)] = gw
		var table_rows := season.record.standings.table(str(cid))
		tables[str(cid)] = table_rows
		var comp := PLRepository.shared().competition(str(cid))
		comps.append({
			"id": str(cid), "name": str(comp.get("name", str(cid))),
			"short": str(comp.get("short_name", str(cid))),
			"matchday": gw,
			"played": season.record.fixtures.played(str(cid)),
			"total": season.record.fixtures.played(str(cid)) + season.record.fixtures.unplayed(str(cid)),
			"complete": season.record.fixtures.unplayed(str(cid)) == 0,
		})
	var primary := str(save.actives[0]) if not save.actives.is_empty() else "PL"


	var ready := 0
	for cid in save.actives:
		if season.record.fixtures.completed_matchdays(str(cid)) >= LeaguePlanner.SUGGEST_AFTER_ROUNDS:
			ready += 1
	return {
		"slug": save.slug,
		"name": save.name(),
		"status": save.status(),
		"date": date,
		"day": FixtureCalendar.day_label(date),
		"matchday": save.matchday(),
		"fixtures": season.record.fixtures.on(date),
		"pending": season.record.fixtures.pending_upto(date),
		"table": tables.get(primary, []),
		"tables": tables,
		"competitions": comps,
		"gameweeks": gameweeks,
		"primary": primary,
		"played": season.record.fixtures.played(),
		"total": season.record.fixtures.played() + season.record.fixtures.unplayed(),
		"rounds": season.record.fixtures.completed_matchdays(primary),
		"can_suggest": ready > 0,
		"interests": season.record.interest.interests(),
		"advance_mode": save.advance_mode(),
		"rules": season.rules.duplicate(true),
		"rules_by": season.rules_by.duplicate(true),
		"complete": complete,
		"summary": season.summary() if complete else {},
	}
