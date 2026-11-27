class_name LeagueGoalDoors
extends RefCounted


static func play(screen, index: int) -> void:
	if screen.mode != screen.MODE_REPORT or not has_clip(screen, index):
		return
	var fixture: Dictionary = screen.report.get("fixture", {})
	screen.goal_highlight_requested.emit(str(fixture.get("id", "")), index)


static func has_clip(screen, index: int) -> bool:
	for row in screen.report.get("highlights", []):
		if int(row.get("goal_index", -1)) == index:
			return true
	return false
