class_name LeagueSaveMigrate
extends RefCounted


static func run() -> void:
	for sql in LeagueSaveSchema.TABLES:
		PLDatabase.execute(sql)
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		LeagueSaveSchema.add_column(table, "competition_id", "TEXT NOT NULL DEFAULT ''")
	LeagueSaveSchema.add_column("league_fixture", "stage", "TEXT NOT NULL DEFAULT ''")
	LeagueSaveSchema.add_column("league_fixture", "leg", "INTEGER NOT NULL DEFAULT 0")
	var hint_rows := LeagueSaveSchema.hint()
	var owner := str(hint_rows[0]) if not hint_rows.is_empty() else "PL"
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		LeagueSaveSchema.backfill(table, owner)
	_rebuild_table_for_two_tables()
	_rebuild_player_stat_for_season()
	_rebuild_absence_for_competition()
	_rebuild_discipline_for_competition()
	for table in LeagueSaveSchema.SEASON_TABLES:
		LeagueSaveSchema.add_column(table, "season_index", "INTEGER NOT NULL DEFAULT 0")
	for sql in LeagueSaveSchema.INDEXES:
		PLDatabase.execute(sql)
	create_two_table_index()
	LeagueRules.migrate(owner)
	LeagueSaveSchema.add_column("club", "reserve_of", "TEXT NOT NULL DEFAULT ''")


static func ensure(save: LeagueSave) -> void:
	if not save.ensure_open():
		return
	for column in LeagueSaveSchema.SIDE_COLUMNS:
		LeagueSaveSchema.add_column("league_table", column)
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		LeagueSaveSchema.add_column(table, "competition_id", "TEXT NOT NULL DEFAULT ''")
		LeagueSaveSchema.backfill(table, str(save.actives[0]) if not save.actives.is_empty() else "")


	LeagueSaveSchema.add_column("match_event", "penalty")
	LeagueSaveSchema.add_column("goal_highlight", "penalty")
	LeagueSaveSchema.add_column("league_fixture", "stage", "TEXT NOT NULL DEFAULT ''")
	LeagueSaveSchema.add_column("league_fixture", "leg", "INTEGER NOT NULL DEFAULT 0")
	LeagueSaveSchema.add_column("club", "reserve_of", "TEXT NOT NULL DEFAULT ''")
	for cid in save.actives:
		PLDatabase.execute(
			"INSERT INTO save_competition (competition_id, active, position) VALUES (?, 1, ?) "
			+ "ON CONFLICT(competition_id) DO UPDATE SET active = 1;",
			[str(cid), save.actives.find(cid)])


static func create_two_table_index() -> void:
	PLDatabase.execute(
		"CREATE UNIQUE INDEX IF NOT EXISTS league_table_pair_idx "
		+ "ON league_table (club_id, competition_id);")


static func _rebuild_table_for_two_tables() -> void:
	var row := PLDatabase.row(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'league_table';")
	if row.is_empty():
		return
	var sql := str(row.get("sql", ""))
	if "PRIMARY KEY (club_id, competition_id)" in sql:
		return
	var have := {}
	for column in PLDatabase.rows("PRAGMA table_info(league_table);"):
		have[str(column["name"])] = true
	if not have.has("competition_id"):
		return
	var carried := ["club_id", "competition_id"]
	for column in ["played", "won", "drawn", "lost", "gf", "ga", "points"] + LeagueSaveSchema.SIDE_COLUMNS:
		if have.has(column):
			carried.append(column)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("ALTER TABLE league_table RENAME TO league_table_pre_two;")
	PLDatabase.execute(LeagueSaveSchema.TABLES[6])
	PLDatabase.execute(
		"INSERT INTO league_table (" + ", ".join(carried) + ") SELECT "
		+ ", ".join(carried) + " FROM league_table_pre_two;")
	PLDatabase.execute("DROP TABLE league_table_pre_two;")
	PLDatabase.transaction("COMMIT;")


static func _rebuild_player_stat_for_season() -> void:
	var row := PLDatabase.row(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = 'league_player_stat';")
	if row.is_empty():
		return
	var sql := str(row.get("sql", ""))
	if "PRIMARY KEY (player_id, competition_id, club_id)" in sql:
		return
	var carried := []
	for column in ["player_id", "competition_id", "club_id", "apps", "goals", "assists",
			"yellow", "red"]:
		carried.append(column)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("ALTER TABLE league_player_stat RENAME TO league_player_stat_pre_season;")
	PLDatabase.execute(LeagueSaveSchema.player_stat_table())
	var sets := carried.duplicate()
	if LeagueSaveSchema.columns("league_player_stat_pre_season").has("season_index"):
		sets.append("season_index")
	PLDatabase.execute(
		"INSERT INTO league_player_stat (" + ", ".join(sets) + ") SELECT "
		+ ", ".join(sets) + " FROM league_player_stat_pre_season;")
	PLDatabase.execute("DROP TABLE league_player_stat_pre_season;")
	PLDatabase.transaction("COMMIT;")


static func _rebuild_absence_for_competition() -> void:
	if not _needs_competition_key("league_absence"):
		return
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("ALTER TABLE league_absence RENAME TO league_absence_pre_comp;")
	PLDatabase.execute(LeagueSaveSchema.create_sql("league_absence"))
	PLDatabase.execute(
		"INSERT INTO league_absence (player_id, competition_id, club_id, kind, grade, "
		+ "days_left, matches_left, started_on, due_on, rate) "
		+ "SELECT a.player_id, CASE WHEN a.kind = 'injury' THEN '' ELSE "
		+ _club_competition("a") + " END, a.club_id, a.kind, a.grade, a.days_left, "
		+ "a.matches_left, a.started_on, a.due_on, a.rate FROM league_absence_pre_comp a;")
	PLDatabase.execute("DROP TABLE league_absence_pre_comp;")
	PLDatabase.transaction("COMMIT;")


static func _rebuild_discipline_for_competition() -> void:
	if not _needs_competition_key("league_discipline"):
		return
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("ALTER TABLE league_discipline RENAME TO league_discipline_pre_comp;")
	PLDatabase.execute(LeagueSaveSchema.create_sql("league_discipline"))
	PLDatabase.execute(
		"INSERT INTO league_discipline (player_id, competition_id, club_id, yellows, yellow_mark) "
		+ "SELECT d.player_id, " + _club_competition("d") + ", d.club_id, "
		+ "COALESCE((SELECT SUM(s.yellow) FROM league_player_stat s "
		+ "WHERE s.player_id = d.player_id AND s.competition_id = "
		+ _club_competition("d") + "), 0), d.yellow_mark "
		+ "FROM league_discipline_pre_comp d;")
	PLDatabase.execute("DROP TABLE league_discipline_pre_comp;")
	PLDatabase.transaction("COMMIT;")


static func _needs_competition_key(table: String) -> bool:
	var row := PLDatabase.row(
		"SELECT sql FROM sqlite_master WHERE type = 'table' AND name = ?;", [table])
	if row.is_empty():
		return false
	return not ("PRIMARY KEY (player_id, competition_id)" in str(row.get("sql", "")))


static func _club_competition(alias: String) -> String:
	return ("COALESCE((SELECT c.competition_id FROM club c WHERE c.id = %s.club_id), '')"
		% alias)
