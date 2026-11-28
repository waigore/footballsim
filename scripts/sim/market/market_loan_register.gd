class_name MarketLoanRegister
extends RefCounted


static func apply(loan: Dictionary) -> bool:
	var player_id := str(loan.get("player_id", ""))
	var loanee := str(loan.get("loanee_club_id", ""))
	var parent := str(loan.get("parent_club_id", ""))
	var index := int(loan.get("season_index", 0))
	var competition_id := competition_of(loanee)
	PLDatabase.execute(
		"UPDATE player_registration SET state = 'closed', reason = 'loaned', deal_id = ? "
		+ "WHERE club_id = ? AND player_id = ? AND state <> 'closed';",
		[str(loan.get("id", "")), parent, player_id])
	return PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index) VALUES (?, ?, ?, 'loan', 'registered', '', ?, ?);",
		[player_id, competition_id, loanee, str(loan.get("id", "")), index]) \
		and PLDatabase.execute("UPDATE player SET club_id = ? WHERE id = ?;", [loanee, player_id]) \
		and MarketContracts.rehome(player_id, loanee) >= 0


static func close(player_id: String, club_id: String) -> void:
	PLDatabase.execute(
		"UPDATE player_registration SET state = 'closed', reason = 'returned' "
		+ "WHERE club_id = ? AND state <> 'closed' AND player_id = ?;",
		[club_id, player_id])


static func mark(player_id: String, club_id: String, index: int) -> void:
	var competition_id := competition_of(club_id)
	if competition_id == "":
		return
	PLDatabase.execute(
		"INSERT OR REPLACE INTO player_registration (player_id, competition_id, club_id, kind, "
		+ "state, reason, deal_id, season_index) VALUES (?, ?, ?, 'permanent', 'registered', '', "
		+ "'', ?);", [player_id, competition_id, club_id, index])


static func competition_of(club_id: String) -> String:
	return str(PLDatabase.row("SELECT competition_id FROM club WHERE id = ?;",
		[club_id]).get("competition_id", ""))
