class_name LeagueSeasonSummary
extends RefCounted


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
	out["cups"] = _cups(season)
	out["one_podium"] = true
	var linked := SeasonSettle.read(season)
	for key in linked.keys():
		out[key] = linked[key]
	_mark_playouts(out)
	return out


static func _mark_playouts(out: Dictionary) -> void:
	var ties: Variant = out.get("playout", {})
	if not ties is Dictionary or (ties as Dictionary).is_empty():
		return
	for section in (out.get("competitions", []) as Array):
		var row: Dictionary = section
		var tie: Variant = (ties as Dictionary).get(str(row.get("id", "")), {})
		if not tie is Dictionary or (tie as Dictionary).is_empty():
			continue
		var entry := {
			"position": int((tie as Dictionary).get("relegated_position", 0)),
			"club": str((tie as Dictionary).get("relegated_club", "")),
			"club_id": str((tie as Dictionary).get("relegated_club_id", "")),
		}
		var relegated: Array = row.get("relegated", [])
		var placed := false
		for i in range(relegated.size()):
			if int((relegated[i] as Dictionary)["position"]) > int(entry["position"]):
				relegated.insert(i, entry)
				placed = true
				break
		if not placed:
			relegated.append(entry)
		row["relegated"] = relegated


static func _cups(season: LeagueSeason) -> Array:
	var out: Array = []
	for cid in LeagueCup.active_ids(season.save):
		var honour := LeagueCupState.honours(str(cid))
		if honour.is_empty():
			continue
		var comp := PLRepository.shared().competition(str(cid))
		honour["name"] = str(comp.get("name", str(cid)))
		honour["short"] = str(comp.get("short_name", str(cid)))
		out.append(honour)
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
