class_name LeaguePromotion
extends RefCounted


const TOP := "BL"
const SECOND := "BL2"


static func movers(season: LeagueSeason, relegation: Dictionary) -> Dictionary:
	if season == null or season.record == null or season.save == null:
		return {}
	if not LeagueRelegation.runs(season.save.actives):
		return {}
	if season.record.fixtures.unplayed() > 0:
		return {}
	var top_rules := season.save.rules_for(TOP)
	var second_rules := season.save.rules_for(SECOND)
	var top_table: Array = season.record.standings.table(TOP)
	var second_table: Array = season.record.standings.table(SECOND)
	var top_drop := int(top_rules.get("relegation_places", 2))
	var second_up := int(second_rules.get("promotion_places", 2))
	if top_table.size() < top_drop or second_table.size() < second_up:
		return {}
	var down: Array = []
	for i in range(top_table.size() - top_drop, top_table.size()):
		down.append(str((top_table[i] as Dictionary)["club_id"]))
	var up: Array = []
	for i in range(second_up):
		up.append(str((second_table[i] as Dictionary)["club_id"]))


	var playoff := ""
	if not relegation.is_empty():
		var winner := str(relegation.get("winner_club_id", ""))
		var loser := str(relegation.get("loser_club_id", ""))
		if winner != "" and loser != "":
			playoff = winner
			if winner == str(relegation.get("second_club_id", "")):
				up.append(winner)
				down.append(loser)
	return {
		"to_top": up, "to_second": down,
		"relegation_winner": playoff,
		"applied": false,
	}


static func apply(season: LeagueSeason, movers: Dictionary) -> bool:
	if season == null or season.record == null or movers.is_empty():
		return false
	var up: Array = movers.get("to_top", [])
	var down: Array = movers.get("to_second", [])
	if up.is_empty() and down.is_empty():
		return false
	if not _needs_swap(up, down):
		return true
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for club_id in up:
		_move(str(club_id), TOP)
	for club_id in down:
		_move(str(club_id), SECOND)
	PLDatabase.transaction("COMMIT;")
	movers["applied"] = true
	PLRepository.shared().invalidate()
	return true


static func _needs_swap(up: Array, down: Array) -> bool:
	for club_id in up:
		if LeaguePyramid.competition_of(str(club_id)) != TOP:
			return true
	for club_id in down:
		if LeaguePyramid.competition_of(str(club_id)) != SECOND:
			return true
	return false


static func _move(club_id: String, competition_id: String) -> void:
	LeaguePyramid.move_club(club_id, competition_id)
