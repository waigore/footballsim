extends SceneTree

## Evidence log for season availability (#155, #156): plays a generated season to
## the winter, then prints what the save is carrying — every club's absentees
## with public wording, the disciplinary ledger, and the month ticks that healed
## players along the way. Pure sim + SQLite, so a headless run is enough.
##
##   godot --path . --headless --script res://tools/absence_report.gd

const SEED := 7711

func _initialize() -> void:
	var season := LeagueSeason.create("Availability Evidence", "generated", "fixture_days", SEED)
	if season == null:
		print("EXIT could not create a season")
		quit()
		return
	var guard := 0
	while str(season.state()["date"]) < "2026-12-15" and guard < 40:
		season.advance()
		guard += 1
	var state := season.state()
	print("SEASON date=%s matchday=%d played=%d" % [
		str(state["date"]), int(state["matchday"]), int(state["played"])])
	var total := 0
	var injuries := 0
	var bans := 0
	for club in TeamData.team_ids():
		var rows := SeasonAvailability.rows(str(club))
		total += rows.size()
		if rows.is_empty():
			continue
		var line := ""
		for row in rows:
			var kind := str(row["kind"])
			if kind == "injury":
				injuries += 1
			else:
				bans += 1
			line += "%s(%s %s) " % [
				str(row.get("player_name", row["player_id"])),
				"INJ" if kind == "injury" else "BAN",
				str(row["grade"]),
			]
		print("CLUB %-4s out=%d %s" % [str(club), rows.size(), line.strip_edges()])
	print("TOTALS out=%d injuries=%d suspensions=%d" % [total, injuries, bans])
	var marks := PLDatabase.rows("SELECT player_id, yellow_mark FROM league_discipline ORDER BY yellow_mark DESC;")
	for row in marks:
		print("DISCIPLINE %s mark=%d" % [str(row["player_id"]), int(row["yellow_mark"])])
	print("ABSENCES rows=%d" % PLDatabase.rows("SELECT player_id FROM league_absence;").size())
	season.close()
	print("EXIT ok")
	quit()
