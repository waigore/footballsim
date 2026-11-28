class_name LeagueFormGuide
extends RefCounted


const LAST := 5

const WIN := "W"
const DRAW := "D"
const LOSS := "L"

const SELECT_PLAYED := (
	"SELECT home_club_id, away_club_id, home_goals, away_goals FROM league_fixture "
	+ "WHERE competition_id = ? AND status = 'played' "
	+ "ORDER BY kickoff, kickoff_time, id;"
)


static func map_for(competition_id: String, limit: int = LAST) -> Dictionary:
	if competition_id == "" or not LeagueLedger.bound():
		return {}
	return fold(PLDatabase.rows(SELECT_PLAYED, [competition_id]), limit)


static func decorate(rows: Array, competition_id: String, limit: int = LAST) -> Array:
	var forms := map_for(competition_id, limit)
	var out: Array = []
	for row in rows:
		var copy: Dictionary = (row as Dictionary).duplicate()
		copy["form"] = forms.get(str(copy.get("club_id", "")), [])
		out.append(copy)
	return out


static func fold(rows: Array, limit: int = LAST) -> Dictionary:
	var out := {}
	for row in rows:
		var home := str(row.get("home_club_id", ""))
		var away := str(row.get("away_club_id", ""))
		var home_goals := int(row.get("home_goals", 0))
		var away_goals := int(row.get("away_goals", 0))
		if home != "":
			_append(out, home, _result(home_goals, away_goals), limit)
		if away != "":
			_append(out, away, _result(away_goals, home_goals), limit)
	return out


static func label(marks: Array) -> String:
	var parts := PackedStringArray()
	for mark in marks:
		parts.append(str(mark))
	return " ".join(parts)


static func _result(scored: int, conceded: int) -> String:
	if scored > conceded:
		return WIN
	if scored == conceded:
		return DRAW
	return LOSS


static func _append(out: Dictionary, club_id: String, mark: String, limit: int) -> void:
	if not out.has(club_id):
		out[club_id] = []
	var marks: Array = out[club_id]
	marks.append(mark)
	var cap := maxi(limit, 1)
	while marks.size() > cap:
		marks.pop_front()
