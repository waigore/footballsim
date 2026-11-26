class_name LeagueSeasonSummary
extends RefCounted

## The season-end podium: champion, runner-up, European places and the drop per
## active competition, read from that league's own saved regulations. Split out
## of `LeagueSeason` so the clock stays one concern; it reads the season's record
## and returns the same plain dictionary the podium always drew.

## The whole podium, or {} until every active competition has played out its
## calendar. The primary league's reading is mirrored at the top so a
## single-league caller reads the keys it always did.
static func build(season: LeagueSeason) -> Dictionary:
	if season == null or season.save == null or season.record == null:
		return {}
	if season.record.fixtures.unplayed() > 0:
		return {}
	var sections: Array = []
	for cid in season.save.actives:
		var section := _section(season, str(cid))
		if not section.is_empty():
			sections.append(section)
	if sections.is_empty():
		return {}
	var out: Dictionary = (sections[0] as Dictionary).duplicate(true)
	out["competitions"] = sections
	out["one_podium"] = true
	return out

static func _section(season: LeagueSeason, competition_id: String) -> Dictionary:
	var rows: Array = season.record.standings.table(competition_id)
	if rows.size() < 2:
		return {}
	var comp_rules := season.save.rules_for(competition_id)
	var places := LeagueRules.places(comp_rules)
	var europe: Array = []
	for i in range(mini(int(places["europe"]), rows.size())):
		europe.append({"position": i + 1, "club": str(rows[i]["club_name"]),
			"zone": str(rows[i]["club_id"])})
	var relegated: Array = []
	for i in range(rows.size() - int(places["relegation"]), rows.size()):
		relegated.append({"position": i + 1, "club": str(rows[i]["club_name"]),
			"club_id": str(rows[i]["club_id"])})
	var comp := PLRepository.shared().competition(competition_id)
	return {
		"id": competition_id,
		"name": str(comp.get("name", competition_id)),
		"short": str(comp.get("short_name", competition_id)),
		"champion": {"club": str(rows[0]["club_name"]), "club_id": str(rows[0]["club_id"]),
			"points": int(rows[0]["points"])},
		"runner_up": {"club": str(rows[1]["club_name"]), "club_id": str(rows[1]["club_id"]),
			"points": int(rows[1]["points"])},
		"europe": europe,
		"relegated": relegated,
		"places": places,
		"rules": comp_rules.duplicate(true),
		"table": rows,
		"top_scorers": season.record.report.top_scorers(5, competition_id),
	}
