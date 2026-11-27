class_name LeaguePlanner
extends RefCounted


const SUGGEST_AFTER_ROUNDS := 5


static func suggest(season) -> Array:
	if season == null or season.record == null or season.save == null:
		return []
	var ids: Array = []
	for cid in season.save.actives:
		var key := str(cid)
		if season.record.fixtures.completed_matchdays(key) < SUGGEST_AFTER_ROUNDS:
			continue
		var top := top_six(season.record, key)
		for fx in season.record.fixtures.pending_upto(season.save.current_date(), key):
			if top.has(str(fx["home_club_id"])) and top.has(str(fx["away_club_id"])):
				ids.append(str(fx["id"]))
	season.record.fixtures.suggest(ids)
	season.state_changed.emit()
	return ids


static func top_six(record, competition_id: String = "") -> Dictionary:
	var out := {}
	var rows: Array = record.standings.table(competition_id)
	for i in range(mini(6, rows.size())):
		out[str(rows[i]["club_id"])] = true
	return out
