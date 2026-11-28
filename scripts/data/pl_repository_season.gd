extends RefCounted


func table(competition_id: String = "") -> Array:
	if LeagueLedger.bound():


		if competition_id == "" or PLCompetitions.season_owns(competition_id):
			return _live_table(competition_id)
		return []
	return _snapshot_table(competition_id)


func _snapshot_table(competition_id: String = "") -> Array:
	var sql := (
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM table_row t JOIN club c ON c.id = t.club_id "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE c.competition_id = ? "
		bindings.append(competition_id)
	return _placed(PLDatabase.rows(
		sql + "ORDER BY c.competition_id, t.position;", bindings))


func _live_table(competition_id: String = "") -> Array:
	if PLDatabase.row(
		"SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'league_table';"
	).is_empty():
		return []
	var sql := (
		"SELECT t.*, c.name AS club_name, c.abbr AS club_abbr, c.color AS club_color "
		+ "FROM league_table t JOIN club c ON c.id = t.club_id "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE t.competition_id = ? "
		bindings.append(competition_id)
	return _placed(PLDatabase.rows(
		sql + "ORDER BY t.competition_id, t.points DESC, (t.gf - t.ga) DESC, t.gf DESC, c.name ASC;",
		bindings))


func _placed(rows: Array) -> Array:
	var place := 0
	var last := ""
	for i in range(rows.size()):
		var comp := str(rows[i].get("competition_id", ""))
		place = 1 if comp != last else place + 1
		last = comp
		rows[i]["position"] = place
	return rows


func leaders(limit: int = 6, stat: String = "goals", competition_id: String = "") -> Array:
	var column := "assists" if stat == "assists" else "goals"
	var sql := (
		"SELECT s.player_id, s.matches, s.goals, s.assists, p.name, p.pos, c.abbr, "
		+ "c.name AS club_name, "
		+ "c.competition_id FROM season_stat s JOIN player p ON p.id = s.player_id "
		+ "JOIN club c ON c.id = p.club_id "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "WHERE c.competition_id = ? "
		bindings.append(competition_id)
	bindings.append(limit)
	return PLDatabase.rows(
		sql + "ORDER BY s.%s DESC, s.assists DESC, p.name LIMIT ?;" % column, bindings)


func fixtures(club_id: String = "", limit: int = 8, competition_id: String = "") -> Array:
	if LeagueLedger.bound() \
			and (competition_id == "" or PLCompetitions.season_owns(competition_id)):
		return LeagueLedger.fixtures(club_id, limit, competition_id)
	var sql := (
		"SELECT f.*, h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, "
		+ "a.name AS away_name FROM fixture f JOIN club h ON h.id = f.home_club_id "
		+ "JOIN club a ON a.id = f.away_club_id WHERE f.played = 1 "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "AND f.competition_id = ? "
		bindings.append(competition_id)
	if club_id.is_empty():
		return PLDatabase.rows(sql + "ORDER BY f.kickoff DESC LIMIT ?;",
			bindings + [limit])
	sql += "AND (f.home_club_id = ? OR f.away_club_id = ?) "
	sql += "ORDER BY f.kickoff DESC, f.id DESC LIMIT ?;"
	return PLDatabase.rows(sql, bindings + [club_id, club_id, limit])


func upcoming(club_id: String = "", limit: int = 6, competition_id: String = "") -> Array:
	if LeagueLedger.bound() \
			and (competition_id == "" or PLCompetitions.season_owns(competition_id)):
		return LeagueLedger.upcoming(club_id, limit, competition_id)
	var sql := (
		"SELECT f.*, h.abbr AS home_abbr, a.abbr AS away_abbr, h.name AS home_name, "
		+ "a.name AS away_name FROM fixture f JOIN club h ON h.id = f.home_club_id "
		+ "JOIN club a ON a.id = f.away_club_id WHERE f.played = 0 "
	)
	var bindings: Array = []
	if competition_id != "":
		sql += "AND f.competition_id = ? "
		bindings.append(competition_id)
	if club_id.is_empty():
		return PLDatabase.rows(sql + "ORDER BY f.kickoff ASC, f.id ASC LIMIT ?;",
			bindings + [limit])
	sql += "AND (f.home_club_id = ? OR f.away_club_id = ?) ORDER BY f.kickoff ASC, f.id ASC LIMIT ?;"
	return PLDatabase.rows(sql, bindings + [club_id, club_id, limit])


func season_active() -> bool:
	return LeagueLedger.bound()


func sim_player(player_id: String) -> Dictionary:
	if LeagueLedger.bound():
		return LeagueLedger.player_line(player_id)
	return PLDatabase.row("SELECT * FROM sim_player_stat WHERE player_id = ?;", [player_id])


func sim_club(club_id: String) -> Dictionary:
	if LeagueLedger.bound():
		return LeagueLedger.club_record(club_id)
	return PLDatabase.row("SELECT * FROM sim_club_stat WHERE club_id = ?;", [club_id])


func sim_scorers(club_id: String, limit: int = 5) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.scorers(club_id, limit)
	return PLDatabase.rows(
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id FROM sim_player_stat s "
		+ "JOIN player p ON p.id = s.player_id WHERE p.club_id = ? AND s.goals > 0 "
		+ "ORDER BY s.goals DESC, s.assists DESC, p.name LIMIT ?;",
		[club_id, limit],
	)


func sim_leaders(limit: int = 5, competition_id: String = "", stat: String = "goals",
		teams: Array = []) -> Array:
	if LeagueLedger.bound():
		return LeagueLedger.leaders(limit, competition_id, stat, teams)
	var column := "assists" if stat == "assists" else "goals"
	var sql := (
		"SELECT s.goals, s.assists, s.apps, p.name, p.id AS player_id, c.abbr, "
		+ "c.name AS club_name, c.id AS club_id, c.competition_id FROM sim_player_stat s "
		+ "JOIN player p ON p.id = s.player_id JOIN club c ON c.id = p.club_id WHERE s.%s > 0" % column
	)
	var bindings: Array = []
	if competition_id != "":
		sql += " AND c.competition_id = ?"
		bindings.append(competition_id)
	if not teams.is_empty():
		var marks := PackedStringArray()
		for i in range(teams.size()):
			marks.append("?")
		sql += " AND c.id IN (" + ",".join(marks) + ")"
		bindings.append_array(teams)
	sql += " ORDER BY s.%s DESC, s.assists DESC, p.name LIMIT ?;" % column
	bindings.append(limit)
	return PLDatabase.rows(sql, bindings)
