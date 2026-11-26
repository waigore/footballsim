class_name LeaguePlanner
extends RefCounted

## The planner's own rule: after five completed gameweeks, point at the upcoming
## clashes between the clubs in the current top six, so a matchday has something
## worth watching. It reads the table and flags fixtures; the clock, the save and
## the match engine stay in `LeagueSeason`.
##
## One rule per active competition: a league's own top six, measured after five
## of that league's own rounds, never a shared table across leagues.

## Completed gameweeks before the planner starts suggesting watches.
const SUGGEST_AFTER_ROUNDS := 5

## Fixture ids the planner flags on the clock's date, or [] before any league has
## a shape to read. Writes the flags onto the ledger and tells the surface.
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

## The six clubs one competition's table currently leads with.
static func top_six(record, competition_id: String = "") -> Dictionary:
	var out := {}
	var rows: Array = record.standings.table(competition_id)
	for i in range(mini(6, rows.size())):
		out[str(rows[i]["club_id"])] = true
	return out
