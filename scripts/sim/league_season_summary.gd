class_name LeagueSeasonSummary
extends RefCounted

## The season-end podium: champion, runner-up, European places and the drop per
## active competition, read from that league's own saved regulations. Split out
## of `LeagueSeason` so the clock stays one concern; it reads the season's record
## and returns the same plain dictionary the podium always drew.

## The whole podium, or {} until every active competition has played out its
## calendar. The primary league's reading is mirrored at the top so a
## single-league caller reads the keys it always did.
##
## The linked tiers ride here too: the English pyramid's play-offs and its
## membership swap (#258/#260), and the German Relegation and its swap (#240).
## Each lane resolves once and applies its swap once; the result is stamped in
## the save (`linked_end`), so a reopened season reads the same brackets and
## never shuffles its clubs a second time — a reopened save recomputes its
## tables from the played fixtures, and a settle run on those tables would read
## a different set of clubs.
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
	_end_of_linked_season(season, out)
	return out

## The linked tiers' end: the stored reading when the season has already settled
## once, otherwise the brackets, the swap and the stamp that freezes them.
static func _end_of_linked_season(season: LeagueSeason, out: Dictionary) -> void:
	var stored: Variant = season.save.meta.get("linked_end", "")
	if stored is String and str(stored) != "":
		var parsed: Variant = JSON.parse_string(str(stored))
		if parsed is Dictionary:
			for key in ["playoffs", "pyramid", "relegation", "promotion"]:
				if (parsed as Dictionary).has(key):
					out[key] = (parsed as Dictionary)[key]
			return
	var payload := {}
	var brackets := LeaguePlayoffs.build_all(season)
	if not brackets.is_empty():
		payload["playoffs"] = brackets
		var pyramid := LeaguePyramid.movers(season, brackets)
		if not pyramid.is_empty():
			LeaguePyramid.apply(season, pyramid)
			payload["pyramid"] = pyramid
	var tie := LeagueRelegation.build(season)
	if not tie.is_empty():
		payload["relegation"] = tie
		var movers := LeaguePromotion.movers(season, tie)
		if not movers.is_empty():
			LeaguePromotion.apply(season, movers)
			payload["promotion"] = movers
	for key in payload.keys():
		out[key] = payload[key]
	if not payload.is_empty():
		season.save.put_meta("linked_end", JSON.stringify(payload))

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
