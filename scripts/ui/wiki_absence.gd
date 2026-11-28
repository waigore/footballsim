class_name WikiAbsence
extends RefCounted


const TAGS := {"injury": "INJ", "suspension": "BAN"}
const SEPARATOR := "  ·  "


static func statuses(club_id: String) -> Dictionary:
	var out := {}
	if club_id == "" or not SeasonAvailability.enabled():
		return out
	for row in SeasonAvailability.rows(club_id):
		var text := status(row, club_id)
		if text != "":
			out[str(row.get("player_id", ""))] = text
	return out


static func status_of(club_id: String, player_id: String) -> String:
	if player_id == "":
		return ""
	return str(statuses(club_id).get(player_id, ""))


static func status(row: Dictionary, club_id: String) -> String:
	var kind := str(row.get("kind", ""))
	if not TAGS.has(kind):
		return ""
	var back := return_text(row, club_id)
	if back == "":
		return str(TAGS[kind])
	return str(TAGS[kind]) + SEPARATOR + back


static func return_text(row: Dictionary, club_id: String) -> String:
	if str(row.get("kind", "")) == SeasonAvailability.KIND_SUSPENSION:
		return ban_return(club_id, int(row.get("matches_left", 0)))
	return injury_return(row)


static func injury_return(row: Dictionary) -> String:
	var due := str(row.get("due_on", ""))
	if due == "":
		var days := int(row.get("days_left", 0))
		if days > 0:
			var today := season_day()
			if today != "":
				due = FixtureCalendar.add_days(today, days)
	var label := FixtureCalendar.day_label(due)
	return "BACK " + label if label != "" else ""


static func ban_return(club_id: String, matches_left: int) -> String:
	if matches_left <= 0 or club_id == "":
		return ""
	var fixtures := PLRepository.shared().upcoming(club_id, matches_left + 1)
	if fixtures.size() <= matches_left:
		return "BACK AFTER SEASON"
	var date := str((fixtures[matches_left] as Dictionary).get("kickoff", ""))
	var label := FixtureCalendar.day_label(date)
	return "BACK " + label if label != "" else "BACK AFTER SEASON"


static func season_day() -> String:
	var season := LeagueSeason.active
	if season == null or season.save == null:
		return ""
	return str(season.save.current_date())
