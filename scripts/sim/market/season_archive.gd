class_name SeasonArchive
extends RefCounted


const LIVE_TABLES := [
	"league_fixture", "league_table", "league_player_stat", "league_absence",
	"league_discipline", "match_event", "goal_highlight", "cup_round", "cup_tie",
]


static func write(season: LeagueSeason, season_index: int) -> Dictionary:
	if season == null or season.save == null or season.record == null:
		return {"clubs": 0, "players": 0}
	var clubs := 0
	for row in season.record.standings.table():
		var ok := PLDatabase.execute(
			"INSERT OR REPLACE INTO season_archive (season_index, competition_id, club_id, "
			+ "club_name, position, played, won, drawn, lost, gf, ga, points) "
			+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			[season_index, str(row.get("competition_id", "")), str(row.get("club_id", "")),
			 str(row.get("club_name", "")), int(row.get("position", 0)),
			 int(row.get("played", 0)), int(row.get("won", 0)), int(row.get("drawn", 0)),
			 int(row.get("lost", 0)), int(row.get("gf", 0)), int(row.get("ga", 0)),
			 int(row.get("points", 0))])
		clubs += 1 if ok else 0
	var players := 0
	for row in PLDatabase.rows(
			"SELECT s.*, p.name AS player_name FROM league_player_stat s "
			+ "LEFT JOIN player p ON p.id = s.player_id;"):
		var ok := PLDatabase.execute(
			"INSERT OR REPLACE INTO player_season_archive (season_index, player_id, "
			+ "player_name, competition_id, club_id, apps, goals, assists, yellow, red) "
			+ "VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);",
			[season_index, str(row.get("player_id", "")), str(row.get("player_name", "")),
			 str(row.get("competition_id", "")), str(row.get("club_id", "")),
			 int(row.get("apps", 0)), int(row.get("goals", 0)), int(row.get("assists", 0)),
			 int(row.get("yellow", 0)), int(row.get("red", 0))])
		players += 1 if ok else 0
	return {"clubs": clubs, "players": players}


static func clear_live(season: LeagueSeason) -> bool:
	if season == null or season.save == null or not season.save.ensure_open():
		return false
	PLDatabase.transaction("BEGIN TRANSACTION;")
	for table in LIVE_TABLES:
		PLDatabase.execute("DELETE FROM %s;" % table)
	PLDatabase.transaction("COMMIT;")
	return true


static func table(season_index: int, competition_id: String) -> Array:
	var sql := ("SELECT * FROM season_archive WHERE season_index = ?")
	var bindings: Array = [season_index]
	if competition_id != "":
		sql += " AND competition_id = ?"
		bindings.append(competition_id)
	return PLDatabase.rows(
		sql + " ORDER BY competition_id, position ASC;", bindings)
