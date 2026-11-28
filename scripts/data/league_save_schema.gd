class_name LeagueSaveSchema
extends RefCounted


const SIDE_COLUMNS := [
	"home_played", "home_won", "home_drawn", "home_lost", "home_gf", "home_ga",
	"away_played", "away_won", "away_drawn", "away_lost", "away_gf", "away_ga",
]

const SEASON_TABLES := [
	"league_fixture", "league_table", "league_player_stat", "cup_round", "cup_tie",
	"season_archive", "player_season_archive", "player_history", "player_contract",
]

const TABLES := [
	"CREATE TABLE IF NOT EXISTS save_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);",
	"CREATE TABLE IF NOT EXISTS save_competition (competition_id TEXT PRIMARY KEY, "
	+ "active INTEGER NOT NULL DEFAULT 1, position INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_interest (club_id TEXT PRIMARY KEY);",
	"CREATE TABLE IF NOT EXISTS cup_round (competition_id TEXT NOT NULL, "
	+ "round_id TEXT NOT NULL, position INTEGER NOT NULL DEFAULT 0, "
	+ "status TEXT NOT NULL DEFAULT 'open', PRIMARY KEY (competition_id, round_id));",
	"CREATE TABLE IF NOT EXISTS cup_tie (competition_id TEXT NOT NULL, "
	+ "round_id TEXT NOT NULL, tie_index INTEGER NOT NULL, "
	+ "home_club_id TEXT NOT NULL, away_club_id TEXT NOT NULL, "
	+ "winner_club_id TEXT NOT NULL DEFAULT '', home_goals INTEGER NOT NULL DEFAULT 0, "
	+ "away_goals INTEGER NOT NULL DEFAULT 0, pens_home INTEGER NOT NULL DEFAULT -1, "
	+ "pens_away INTEGER NOT NULL DEFAULT -1, extra_time INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (competition_id, round_id, tie_index));",
	"CREATE TABLE IF NOT EXISTS league_fixture (id TEXT PRIMARY KEY, "
	+ "competition_id TEXT NOT NULL DEFAULT '', matchday INTEGER NOT NULL, "
	+ "kickoff TEXT NOT NULL, kickoff_time TEXT NOT NULL DEFAULT '', "
	+ "home_club_id TEXT NOT NULL, away_club_id TEXT NOT NULL, "
	+ "home_goals INTEGER NOT NULL DEFAULT 0, away_goals INTEGER NOT NULL DEFAULT 0, "
	+ "status TEXT NOT NULL DEFAULT 'pending', watched INTEGER NOT NULL DEFAULT 0, "
	+ "suggested INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_table (club_id TEXT NOT NULL, "
	+ "competition_id TEXT NOT NULL DEFAULT '', "
	+ "played INTEGER NOT NULL DEFAULT 0, won INTEGER NOT NULL DEFAULT 0, "
	+ "drawn INTEGER NOT NULL DEFAULT 0, lost INTEGER NOT NULL DEFAULT 0, "
	+ "gf INTEGER NOT NULL DEFAULT 0, ga INTEGER NOT NULL DEFAULT 0, "
	+ "points INTEGER NOT NULL DEFAULT 0, "
	+ "home_played INTEGER NOT NULL DEFAULT 0, home_won INTEGER NOT NULL DEFAULT 0, "
	+ "home_drawn INTEGER NOT NULL DEFAULT 0, home_lost INTEGER NOT NULL DEFAULT 0, "
	+ "home_gf INTEGER NOT NULL DEFAULT 0, home_ga INTEGER NOT NULL DEFAULT 0, "
	+ "away_played INTEGER NOT NULL DEFAULT 0, away_won INTEGER NOT NULL DEFAULT 0, "
	+ "away_drawn INTEGER NOT NULL DEFAULT 0, away_lost INTEGER NOT NULL DEFAULT 0, "
	+ "away_gf INTEGER NOT NULL DEFAULT 0, away_ga INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (club_id, competition_id));",
	"CREATE TABLE IF NOT EXISTS match_event (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "fixture_id TEXT NOT NULL, minute INTEGER NOT NULL, kind TEXT NOT NULL, "
	+ "player_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL DEFAULT '', "
	+ "detail TEXT NOT NULL DEFAULT '', penalty INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS league_player_stat (player_id TEXT NOT NULL, "
	+ "competition_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL, "
	+ "season_index INTEGER NOT NULL DEFAULT 0, "
	+ "apps INTEGER NOT NULL DEFAULT 0, goals INTEGER NOT NULL DEFAULT 0, "
	+ "assists INTEGER NOT NULL DEFAULT 0, yellow INTEGER NOT NULL DEFAULT 0, "
	+ "red INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (player_id, competition_id, club_id));",
	"CREATE TABLE IF NOT EXISTS league_absence (player_id TEXT NOT NULL, "
	+ "competition_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL, kind TEXT NOT NULL, "
	+ "grade TEXT NOT NULL DEFAULT '', days_left INTEGER NOT NULL DEFAULT 0, "
	+ "matches_left INTEGER NOT NULL DEFAULT 0, started_on TEXT NOT NULL DEFAULT '', "
	+ "due_on TEXT NOT NULL DEFAULT '', rate REAL NOT NULL DEFAULT 1.0, "
	+ "PRIMARY KEY (player_id, competition_id));",
	"CREATE TABLE IF NOT EXISTS league_discipline (player_id TEXT NOT NULL, "
	+ "competition_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL, "
	+ "yellows INTEGER NOT NULL DEFAULT 0, yellow_mark INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (player_id, competition_id));",
	"CREATE TABLE IF NOT EXISTS goal_highlight (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "fixture_id TEXT NOT NULL, goal_index INTEGER NOT NULL, "
	+ "match_event_id INTEGER NOT NULL DEFAULT 0, minute INTEGER NOT NULL DEFAULT 0, "
	+ "club_id TEXT NOT NULL DEFAULT '', scorer_id TEXT NOT NULL DEFAULT '', "
	+ "scorer_name TEXT NOT NULL DEFAULT '', assist_id TEXT NOT NULL DEFAULT '', "
	+ "assist_name TEXT NOT NULL DEFAULT '', commentary TEXT NOT NULL DEFAULT '', "
	+ "source TEXT NOT NULL DEFAULT 'auto', codec TEXT NOT NULL DEFAULT '', "
	+ "version INTEGER NOT NULL DEFAULT 0, home_club_id TEXT NOT NULL DEFAULT '', "
	+ "away_club_id TEXT NOT NULL DEFAULT '', bytes BLOB, "
	+ "penalty INTEGER NOT NULL DEFAULT 0, UNIQUE(fixture_id, goal_index));",
	"CREATE TABLE IF NOT EXISTS season_archive (season_index INTEGER NOT NULL, "
	+ "competition_id TEXT NOT NULL, club_id TEXT NOT NULL, "
	+ "club_name TEXT NOT NULL DEFAULT '', position INTEGER NOT NULL DEFAULT 0, "
	+ "played INTEGER NOT NULL DEFAULT 0, won INTEGER NOT NULL DEFAULT 0, "
	+ "drawn INTEGER NOT NULL DEFAULT 0, lost INTEGER NOT NULL DEFAULT 0, "
	+ "gf INTEGER NOT NULL DEFAULT 0, ga INTEGER NOT NULL DEFAULT 0, "
	+ "points INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (season_index, competition_id, club_id));",
	"CREATE TABLE IF NOT EXISTS player_season_archive (season_index INTEGER NOT NULL, "
	+ "player_id TEXT NOT NULL, player_name TEXT NOT NULL DEFAULT '', "
	+ "competition_id TEXT NOT NULL DEFAULT '', club_id TEXT NOT NULL, "
	+ "apps INTEGER NOT NULL DEFAULT 0, goals INTEGER NOT NULL DEFAULT 0, "
	+ "assists INTEGER NOT NULL DEFAULT 0, yellow INTEGER NOT NULL DEFAULT 0, "
	+ "red INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (season_index, player_id, competition_id, club_id));",
	"CREATE TABLE IF NOT EXISTS player_history (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "player_id TEXT NOT NULL, season_index INTEGER NOT NULL, "
	+ "club_id TEXT NOT NULL DEFAULT '', competition_id TEXT NOT NULL DEFAULT '', "
	+ "kind TEXT NOT NULL DEFAULT 'spell', from_date TEXT NOT NULL DEFAULT '', "
	+ "to_date TEXT NOT NULL DEFAULT '', "
	+ "UNIQUE (player_id, season_index, club_id, kind));",
	"CREATE TABLE IF NOT EXISTS player_contract (player_id TEXT NOT NULL, "
	+ "club_id TEXT NOT NULL, season_index INTEGER NOT NULL DEFAULT 0, "
	+ "start_date TEXT NOT NULL, end_date TEXT NOT NULL, "
	+ "wage INTEGER NOT NULL DEFAULT 0, signing_bonus INTEGER NOT NULL DEFAULT 0, "
	+ "agent_fee INTEGER NOT NULL DEFAULT 0, release_clause INTEGER NOT NULL DEFAULT 0, "
	+ "option_years INTEGER NOT NULL DEFAULT 0, status TEXT NOT NULL DEFAULT 'active', "
	+ "deal_id TEXT NOT NULL DEFAULT '', declined INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (player_id, start_date));",
	"CREATE TABLE IF NOT EXISTS club_finance (club_id TEXT PRIMARY KEY, "
	+ "cash INTEGER NOT NULL DEFAULT 0, reputation INTEGER NOT NULL DEFAULT 0, "
	+ "revenue_base INTEGER NOT NULL DEFAULT 0, wage_budget INTEGER NOT NULL DEFAULT 0, "
	+ "updated_on TEXT NOT NULL DEFAULT '', season_index INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS club_ledger (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "season_index INTEGER NOT NULL DEFAULT 0, date TEXT NOT NULL DEFAULT '', "
	+ "club_id TEXT NOT NULL, kind TEXT NOT NULL, amount INTEGER NOT NULL DEFAULT 0, "
	+ "counterparty TEXT NOT NULL DEFAULT '', player_id TEXT NOT NULL DEFAULT '', "
	+ "deal_id TEXT NOT NULL DEFAULT '', amortisation INTEGER NOT NULL DEFAULT 0);",
	"CREATE TABLE IF NOT EXISTS deal (id TEXT PRIMARY KEY, "
	+ "kind TEXT NOT NULL DEFAULT 'permanent', season_index INTEGER NOT NULL DEFAULT 0, "
	+ "state TEXT NOT NULL DEFAULT 'proposed', from_club_id TEXT NOT NULL DEFAULT '', "
	+ "to_club_id TEXT NOT NULL, player_id TEXT NOT NULL, fee INTEGER NOT NULL DEFAULT 0, "
	+ "wage INTEGER NOT NULL DEFAULT 0, signing_bonus INTEGER NOT NULL DEFAULT 0, "
	+ "agent_fee INTEGER NOT NULL DEFAULT 0, years INTEGER NOT NULL DEFAULT 1, "
	+ "sell_on REAL NOT NULL DEFAULT 0, window_id TEXT NOT NULL DEFAULT '', "
	+ "reason TEXT NOT NULL DEFAULT '', god TEXT NOT NULL DEFAULT '', "
	+ "opened_on TEXT NOT NULL DEFAULT '', signed_on TEXT NOT NULL DEFAULT '', "
	+ "clears_on TEXT NOT NULL DEFAULT '', deal_terms TEXT NOT NULL DEFAULT '{}');",
	"CREATE TABLE IF NOT EXISTS deal_event (id INTEGER PRIMARY KEY AUTOINCREMENT, "
	+ "deal_id TEXT NOT NULL, date TEXT NOT NULL DEFAULT '', state TEXT NOT NULL, "
	+ "reason TEXT NOT NULL DEFAULT '');",
	"CREATE TABLE IF NOT EXISTS player_registration (player_id TEXT NOT NULL, "
	+ "competition_id TEXT NOT NULL, club_id TEXT NOT NULL DEFAULT '', "
	+ "kind TEXT NOT NULL DEFAULT 'permanent', state TEXT NOT NULL DEFAULT 'registered', "
	+ "reason TEXT NOT NULL DEFAULT '', deal_id TEXT NOT NULL DEFAULT '', "
	+ "season_index INTEGER NOT NULL DEFAULT 0, "
	+ "PRIMARY KEY (player_id, competition_id));",
]

const INDEXES := [
	"CREATE INDEX IF NOT EXISTS league_fixture_kickoff_idx ON league_fixture (kickoff);",
	"CREATE INDEX IF NOT EXISTS league_fixture_comp_idx ON league_fixture (competition_id);",
	"CREATE INDEX IF NOT EXISTS match_event_fixture_idx ON match_event (fixture_id);",
	"CREATE INDEX IF NOT EXISTS goal_highlight_fixture_idx ON goal_highlight (fixture_id);",
	"CREATE INDEX IF NOT EXISTS cup_tie_round_idx ON cup_tie (competition_id, round_id);",
	"CREATE INDEX IF NOT EXISTS player_contract_club_idx ON player_contract (club_id, status);",
	"CREATE INDEX IF NOT EXISTS club_ledger_club_idx ON club_ledger (club_id, season_index);",
	"CREATE INDEX IF NOT EXISTS club_ledger_season_idx ON club_ledger (season_index, date);",
	"CREATE INDEX IF NOT EXISTS deal_player_idx ON deal (player_id, state);",
	"CREATE INDEX IF NOT EXISTS deal_event_deal_idx ON deal_event (deal_id);",
	"CREATE INDEX IF NOT EXISTS player_registration_club_idx ON player_registration (club_id, state);",
]


static func active_from_disk() -> Array:
	var out: Array = []
	for row in PLDatabase.rows(
			"SELECT competition_id FROM save_competition WHERE active = 1 ORDER BY position, competition_id;"):
		out.append(str(row["competition_id"]))
	if not out.is_empty():
		return out
	return hint()


static func hint() -> Array:
	var row := PLDatabase.row("SELECT value FROM save_meta WHERE key = 'competitions';")
	if not row.is_empty() and str(row.get("value", "")) != "":
		var out: Array = []
		for part in str(row["value"]).split(",", false):
			if part != "":
				out.append(part)
		if not out.is_empty():
			return out
	var fx := PLDatabase.row("SELECT competition_id FROM league_fixture WHERE competition_id <> '' LIMIT 1;")
	if not fx.is_empty():
		return [str(fx["competition_id"])]
	var comp := PLDatabase.row("SELECT id FROM competition ORDER BY rowid LIMIT 1;")
	return [str(comp.get("id", "PL"))] if not comp.is_empty() else ["PL"]


static func valid(wanted: Array) -> Array:
	var known: Array = []
	for row in PLDatabase.rows("SELECT id FROM competition ORDER BY rowid;"):
		known.append(str(row["id"]))
	var out: Array = []
	for cid in wanted:
		var key := str(cid)
		if known.has(key) and not out.has(key):
			out.append(key)
	if out.is_empty():
		out.append("PL" if known.has("PL") or known.is_empty() else str(known[0]))
	return out


static func migrate() -> void:
	for sql in TABLES:
		PLDatabase.execute(sql)
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		add_column(table, "competition_id", "TEXT NOT NULL DEFAULT ''")
	add_column("league_fixture", "stage", "TEXT NOT NULL DEFAULT ''")
	add_column("league_fixture", "leg", "INTEGER NOT NULL DEFAULT 0")
	var hint_rows := hint()
	var owner := str(hint_rows[0]) if not hint_rows.is_empty() else "PL"
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		backfill(table, owner)
	_rebuild_table_for_two_tables()
	_rebuild_player_stat_for_season()
	_rebuild_absence_for_competition()
	_rebuild_discipline_for_competition()
	for table in SEASON_TABLES:
		add_column(table, "season_index", "INTEGER NOT NULL DEFAULT 0")
	for sql in INDEXES:
		PLDatabase.execute(sql)
	create_two_table_index()
	LeagueRules.migrate(owner)
	add_column("club", "reserve_of", "TEXT NOT NULL DEFAULT ''")


static func ensure_schema(save: LeagueSave) -> void:
	if not save.ensure_open():
		return
	for column in SIDE_COLUMNS:
		add_column("league_table", column)
	for table in ["league_fixture", "league_table", "league_player_stat"]:
		add_column(table, "competition_id", "TEXT NOT NULL DEFAULT ''")
		backfill(table, str(save.actives[0]) if not save.actives.is_empty() else "")


	add_column("match_event", "penalty")
	add_column("goal_highlight", "penalty")
	add_column("league_fixture", "stage", "TEXT NOT NULL DEFAULT ''")
	add_column("league_fixture", "leg", "INTEGER NOT NULL DEFAULT 0")
	add_column("club", "reserve_of", "TEXT NOT NULL DEFAULT ''")
	for cid in save.actives:
		PLDatabase.execute(
			"INSERT INTO save_competition (competition_id, active, position) VALUES (?, 1, ?) "
			+ "ON CONFLICT(competition_id) DO UPDATE SET active = 1;",
			[str(cid), save.actives.find(cid)])


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
	for column in ["played", "won", "drawn", "lost", "gf", "ga", "points"] + SIDE_COLUMNS:
		if have.has(column):
			carried.append(column)
	PLDatabase.transaction("BEGIN TRANSACTION;")
	PLDatabase.execute("ALTER TABLE league_table RENAME TO league_table_pre_two;")
	PLDatabase.execute(TABLES[6])
	PLDatabase.execute(
		"INSERT INTO league_table (" + ", ".join(carried) + ") SELECT "
		+ ", ".join(carried) + " FROM league_table_pre_two;")
	PLDatabase.execute("DROP TABLE league_table_pre_two;")
	PLDatabase.transaction("COMMIT;")


static func create_two_table_index() -> void:
	PLDatabase.execute(
		"CREATE UNIQUE INDEX IF NOT EXISTS league_table_pair_idx "
		+ "ON league_table (club_id, competition_id);")


static func player_stat_table() -> String:
	for sql in TABLES:
		if "CREATE TABLE IF NOT EXISTS league_player_stat (" in sql:
			return sql
	return ""


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
	PLDatabase.execute(player_stat_table())
	var sets := carried.duplicate()
	if _columns("league_player_stat_pre_season").has("season_index"):
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
	PLDatabase.execute(_create_sql("league_absence"))
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
	PLDatabase.execute(_create_sql("league_discipline"))
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


static func _create_sql(name: String) -> String:
	for sql in TABLES:
		if "CREATE TABLE IF NOT EXISTS %s (" % name in sql:
			return sql
	return ""


static func _columns(table: String) -> Dictionary:
	var out := {}
	for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
		out[str(row["name"])] = true
	return out


static func add_column(table: String, column: String,
		spec: String = "INTEGER NOT NULL DEFAULT 0") -> void:
	var have := {}
	for row in PLDatabase.rows("PRAGMA table_info(%s);" % table):
		have[str(row["name"])] = true
	if have.has(column):
		return
	PLDatabase.execute("ALTER TABLE %s ADD COLUMN %s %s;" % [table, column, spec])


static func backfill(table: String, competition_id: String) -> void:
	if competition_id == "":
		return
	PLDatabase.execute(
		"UPDATE %s SET competition_id = ? WHERE competition_id = '' OR competition_id IS NULL;"
		% table, [competition_id])
