class_name LeagueGoalDoors
extends RefCounted

## The report's numbered goal doors: the digit keys that play a stored clip, and
## the `goal:` press the report's ▶ rows send.
##
## Split out of `LeagueDoors` (the dispatch table is at its size budget) and
## written like `LeagueCalendar`: static helpers that read the report on the
## screen and name the clip through the screen's own signal. The host owns the
## viewer; this module never starts one.

## Play one goal of the report on screen. Only the report pose answers, and only
## for an ordinal the report actually stored.
static func play(screen, index: int) -> void:
	if screen.mode != screen.MODE_REPORT or not has_clip(screen, index):
		return
	var fixture: Dictionary = screen.report.get("fixture", {})
	screen.goal_highlight_requested.emit(str(fixture.get("id", "")), index)

## True when the report on screen carries a stored clip for a goal ordinal.
static func has_clip(screen, index: int) -> bool:
	for row in screen.report.get("highlights", []):
		if int(row.get("goal_index", -1)) == index:
			return true
	return false
