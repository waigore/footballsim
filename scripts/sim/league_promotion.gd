class_name LeaguePromotion
extends RefCounted

## Who belongs in which German tier once the season is over (#240).
##
## The Bundesliga's 17th and 18th drop and 2. Bundesliga's 1st and 2nd rise; the
## Relegation's winner takes the last top-flight place and its loser the last
## second-tier one. The result is applied to the save's own membership: the
## `competition_member` rows, the clubs' `competition_id` and every fixture's
## competition move together, so the encyclopedia, the table identity and a
## reopened save all read the same two leagues afterwards.
##
## A save that does not run both German tiers has nothing to swap, and no save
## starts a second season: the swap is the last thing a season does.

const TOP := "BL"
const SECOND := "BL2"

## The movers for a finished season, read from its own tables and the Relegation
## result. Empty until both calendars are played out.
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
	# The Relegation's winner takes the top-flight place. When the top-flight
	# club holds it, nobody moves; when the second-tier club takes it, its club
	# rises and the top-flight loser drops.
	var playoff := ""
	if not relegation.is_empty():
		var winner := str(relegation.get("winner_club_id", ""))
		var loser := str(relegation.get("loser_club_id", ""))
		if winner != "" and loser != "":
			playoff = winner
			if winner.begins_with(SECOND + "-"):
				up.append(winner)
				down.append(loser)
	return {
		"to_top": up, "to_second": down,
		"relegation_winner": playoff,
		"applied": false,
	}

## Apply a set of movers to the save. Idempotent: a save whose clubs already sit
## in the right tier is left alone, so reopening a finished season cannot swap
## them twice.
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

## True while any mover still sits in the tier it is leaving.
static func _needs_swap(up: Array, down: Array) -> bool:
	for club_id in up:
		if _competition_of(str(club_id)) != TOP:
			return true
	for club_id in down:
		if _competition_of(str(club_id)) != SECOND:
			return true
	return false

static func _competition_of(club_id: String) -> String:
	var row := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return str(row.get("competition_id", ""))

## One club's identity: its membership row and its club row. The season's own
## fixtures and table rows are the record of what was played, so they stay in
## the competition that was played — only who belongs where changes.
static func _move(club_id: String, competition_id: String) -> void:
	PLDatabase.execute("DELETE FROM competition_member WHERE member_kind = 'club' AND member_id = ?;",
		[club_id])
	PLDatabase.execute("INSERT OR REPLACE INTO competition_member (competition_id, member_kind, "
		+ "member_id, role) VALUES (?, 'club', ?, 'member');", [competition_id, club_id])
	PLDatabase.execute("UPDATE club SET competition_id = ? WHERE id = ?;", [competition_id, club_id])
