class_name LeaguePyramid
extends RefCounted


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
		var to_top: Array = _automatic(season, bottom, lower_rules, up)
		if to_top.size() < up:
			continue
		var winner := str(bracket.get("winner_club_id", ""))
		if winner != "":
			to_top.append(winner)
		var to_bottom: Array = []
		for i in range(top_table.size() - down, top_table.size()):
			to_bottom.append(str((top_table[i] as Dictionary)["club_id"]))


		var move := mini(to_top.size(), to_bottom.size())
		links.append({
			"top": top, "bottom": bottom,
			"to_top": to_top.slice(0, move), "to_bottom": to_bottom.slice(0, move),
			"playoff": winner,
		})
	if links.is_empty():
		return {}
	return {"links": links, "applied": false}


static func _automatic(season: LeagueSeason, competition_id: String, rules: Dictionary,
		up: int) -> Array:
	if LeagueSegunda.format(rules):
		return LeagueSegunda.automatic(season, competition_id, rules)
	var table: Array = season.record.standings.table(competition_id)
	var out: Array = []
	for i in range(mini(up, table.size())):
		out.append(str((table[i] as Dictionary)["club_id"]))
	return out


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


static func competition_of(club_id: String) -> String:
	var row := PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;", [club_id])
	return str(row.get("competition_id", ""))


static func move_club(club_id: String, competition_id: String) -> void:
	PLDatabase.execute("DELETE FROM competition_member WHERE member_kind = 'club' AND member_id = ?;",
		[club_id])
	PLDatabase.execute("INSERT OR REPLACE INTO competition_member (competition_id, member_kind, "
		+ "member_id, role) VALUES (?, 'club', ?, 'member');", [competition_id, club_id])
	PLDatabase.execute("UPDATE club SET competition_id = ? WHERE id = ?;", [competition_id, club_id])
