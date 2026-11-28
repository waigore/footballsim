class_name LeagueReportActions
extends RefCounted


static func press(screen: LeagueScreen, id: String) -> bool:
	if id.begins_with(LeagueReportSheet.ALL_CHIP):
		var comp := id.substr(LeagueReportSheet.ALL_CHIP.length())
		screen.report_filter["league"] = "" \
			if str(screen.report_filter.get("league", "")) == comp else comp
		screen.refresh()
		return true
	if id == LeagueReportSheet.INTEREST_CHIP:
		screen.report_filter["interest"] = not bool(screen.report_filter.get("interest", false))
		screen.refresh()
		return true
	return false


static func reset(screen: LeagueScreen) -> void:
	screen.report_filter = {"league": "", "interest": false}
