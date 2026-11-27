class_name LeaguePyramid
extends RefCounted

## The end of a linked season's English pyramid (#258/#260): who belongs where
## once every active calendar is played, and the one swap that puts them there.
##
## Only an adjacent pair of *active* tiers swaps. A tier whose neighbour is not
## playing keeps its clubs, so the deepest active tier's drop has nowhere to go
## — the National League's bottom four read RELEGATED and stay — and the strip
## above an inactive tier takes no promotion. Nothing starts a second season:
## the swap is the last thing a season does, and applying it twice changes
## nothing.
##
## The club counts are the regulations' own: the tier below sends its automatic
## promotion places plus the play-off winner, and the tier above sends exactly
## its relegation places. The two match by construction (a test pins every
## shipped pair), so a tier never grows or shrinks.
##
## The German pair is not this lane: its last place is a cross-tier Relegation
## (`LeagueRelegation`), not a mini-tournament, so `LeaguePromotion` settles it.
## Both read the same tier graph (`LeagueTiers`), which is what makes the
## countries coexist in one save.

## The swap for a finished season, or {} when no English pair can settle.
static func movers(season: LeagueSeason, brackets: Dictionary) -> Dictionary:
	if season == null or season.save == null or season.record == null:
		return {}
	if season.record.fixtures.unplayed() > 0 or brackets.is_empty():
		return {}
	var links: Array = []
	for pair in LeagueTiers.pairs(season.save.actives):
		var top := str(pair[0])
		var bottom := str(pair[1])
		var lower_rules := season.save.rules_for(bottom)
		if str(lower_rules.get("playoff_format", "")) == "":
			continue
		var bracket: Dictionary = brackets.get(bottom, {})
		if bracket.is_empty():
			continue
		var up := int(lower_rules.get("promotion_places", 0))
		var down := int(season.save.rules_for(top).get("relegation_places", 0))
		var top_table: Array = season.record.standings.table(top)
		var bottom_table: Array = season.record.standings.table(bottom)
		if top_table.size() < down or bottom_table.size() < up + 1:
			continue
		var to_top: Array = []
		for i in range(up):
			to_top.append(str((bottom_table[i] as Dictionary)["club_id"]))
		var winner := str(bracket.get("winner_club_id", ""))
		if winner != "":
			to_top.append(winner)
		var to_bottom: Array = []
		for i in range(top_table.size() - down, top_table.size()):
			to_bottom.append(str((top_table[i] as Dictionary)["club_id"]))
		# A tier never grows: the smaller side decides, so a hand-edited set of
		# regulations can cost a promotion but can never add clubs to a league.
		var move := mini(to_top.size(), to_bottom.size())
		links.append({
			"top": top, "bottom": bottom,
			"to_top": to_top.slice(0, move), "to_bottom": to_bottom.slice(0, move),
			"playoff": winner,
		})
	if links.is_empty():
		return {}
	return {"links": links, "applied": false}

## Apply a set of swaps to the save. Idempotent: a club already filed in its new
## tier is left alone, so reopening a finished season cannot move it twice.
static func apply(season: LeagueSeason, movers: Dictionary) -> bool:
	if season == null or season.record == null or movers.is_empty():
		return false
	var links: Array = movers.get("links", [])
	if links.is_empty():
		return false
	var moves: Array = []
	for link in links:
		for club_id in link["to_top"]:
			moves.append([str(club_id), str(link["top"])])
		for club_id in link["to_bottom"]:
			moves.append([str(club_id), str(link["bottom"])])
	var needed: Array = []
	for move in moves:
		if competition_of(str(move[0])) != str(move[1]):
			needed.append(move)
	if needed.is_empty():
		movers["applied"] = false
		return true
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for move in needed:
		move_club(str(move[0]), str(move[1]))
	PLDatabase.transaction("COMMIT;")
	PLRepository.shared().invalidate()
	movers["applied"] = true
	return true

## A club's own competition, read from the save.
static func competition_of(club_id: String) -> String:
	var row := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return str(row.get("competition_id", ""))

## One club's identity: its membership row and its club row. The season's own
## fixtures and table rows are the record of what was played, so they stay in
## the competition that was played — only who belongs where changes.
static func move_club(club_id: String, competition_id: String) -> void:
	PLDatabase.execute("DELETE FROM competition_member WHERE member_kind = 'club' AND member_id = ?;",
		[club_id])
	PLDatabase.execute("INSERT OR REPLACE INTO competition_member (competition_id, member_kind, "
		+ "member_id, role) VALUES (?, 'club', ?, 'member');", [competition_id, club_id])
	PLDatabase.execute("UPDATE club SET competition_id = ? WHERE id = ?;", [competition_id, club_id])
