class_name LeagueSummary
extends RefCounted

## The season-end reading: champion, runner-up, European places, the drop and
## the top scorers, all from the saved regulations and the played ledger.
##
## Kept out of `LeagueSeason` (at its P3 size ratchet) and pure: it reads a
## record and a rule set and returns the dictionary the podium paints.

static func build(record: LeagueRecord, rules: Dictionary) -> Dictionary:
	if record == null or record.unplayed() > 0:
		return {}
	var rows := record.table()
	if rows.size() < 20:
		return {}
	var places := LeagueRules.places(rules)
	var europe: Array = []
	for i in range(mini(int(places["europe"]), rows.size())):
		europe.append({"position": i + 1, "club": str(rows[i]["club_name"]), "zone": str(rows[i]["club_id"])})
	var relegated: Array = []
	for i in range(rows.size() - int(places["relegation"]), rows.size()):
		relegated.append({"position": i + 1, "club": str(rows[i]["club_name"]), "club_id": str(rows[i]["club_id"])})
	return {
		"champion": {"club": str(rows[0]["club_name"]), "club_id": str(rows[0]["club_id"]), "points": int(rows[0]["points"])},
		"runner_up": {"club": str(rows[1]["club_name"]), "club_id": str(rows[1]["club_id"]), "points": int(rows[1]["points"])},
		"europe": europe,
		"relegated": relegated,
		"places": places,
		"top_scorers": record.top_scorers(5),
	}
